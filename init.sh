#!/bin/bash
# Copyright (C) 2018  Mikkel Oscar Lyderik Larsen
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Import travis_functions.
source "${TRAVIS_HOME}/.travis/functions"

# Proxy time/fold functions
shopt -s expand_aliases
alias time_start="travis_time_start"
alias time_stop="travis_time_finish"
alias fold_start="travis_fold start"
alias fold_stop="travis_fold end"

# Add blue color ANSI code
export ANSI_BLUE='\033[1;34m'

arch_msg() {
  echo -e "${ANSI_BLUE}$*${ANSI_RESET}"
}


cd /build || exit

if [ -n "$CC" ]; then
  # store travis CC
  TRAVIS_CC=$CC
  TRAVIS_CXX=$CXX
  # reset to gcc for building arch packages
  CC=gcc
  CXX=g++
fi

# /etc/pacman.conf repository line
repo_line=70

decode_config() {
  base64 -d <<<"$@"
}

# PS4 configuration line for 'bash -x' script execution
bash_ps4() {
  echo "readonly PS4='\\\$ ${FUNCNAME[1]}:\${LINENO} ---8<--- '";
}

# read arch-travis config from env
read_config() {
  mapfile -t -d $'\0' CONFIG_BEFORE_INSTALL < <(decode_config "${CONFIG_BEFORE_INSTALL}")
  mapfile -t -d $'\0' CONFIG_BUILD_SCRIPTS  < <(decode_config "${CONFIG_BUILD_SCRIPTS}")
  mapfile -t -d $'\n' CONFIG_PACKAGES       < <(decode_config "${CONFIG_PACKAGES}")
  mapfile -t -d $'\n' CONFIG_REPOS          < <(decode_config "${CONFIG_REPOS}")
}

# add custom repositories to pacman.conf
add_repositories() {
  if [ ${#CONFIG_REPOS[@]} -gt 0 ]; then
    fold_start "Add Repositories"
    for r in "${CONFIG_REPOS[@]}"; do
      arch_msg "repository: $r"
      IFS=" " read -r -a splitarr <<< "${r//=/ }"
      ((repo_line+=1))
      sudo sed -i "${repo_line}i[${splitarr[0]}]" /etc/pacman.conf
      ((repo_line+=1))
      sudo sed -i "${repo_line}iServer = ${splitarr[1]}\n" /etc/pacman.conf
      ((repo_line+=1))
    done
    fold_start "Add Repositories"

    # update repos
    fold_start "Update Repositories"
    sudo pacman -Syy
    fold_stop  "Update Repositories"
  fi
}

# run before_install script defined in .travis.yml
before_install() {
  if [ ${#CONFIG_BEFORE_INSTALL[@]} -gt 0 ]; then
    fold_start "Run before_install"
    for script in "${CONFIG_BEFORE_INSTALL[@]}"; do
      arch_msg "Evaluate:\n$(sed 's/^/$ /g'<<<"$script")"
      eval "$script" || exit $?
    done
    fold_stop  "Run before_install"
  fi
}

# update reflector to prevent dead mirror causing build to fail.
update_reflector() {
  fold_start "Update Reflector"
  sudo reflector --verbose -l 10 --sort rate --save /etc/pacman.d/mirrorlist
  fold_stop  "Update Reflector"
}

# upgrade system to avoid partial upgrade states
upgrade_system() {
  fold_start "Upgrade System"
  sudo pacman -Syu --noconfirm
  fold_stop  "Upgrade System"
}

# install packages defined in .travis.yml
install_packages() {
  if [ ${#CONFIG_PACKAGES[@]} -gt 0 ]; then
    arch_msg "Install Packages"
    for pkg in "${CONFIG_PACKAGES[@]}"; do
      time_start "Install $pkg"
      yay -S "$pkg" --noconfirm --needed --useask --gpgflags "--keyserver hkp://pool.sks-keyservers.net" --mflags="$(env|grep ^TRAVIS)" || exit $?
      time_stop "Install $pkg"
    done
  fi
}

# run build scripts defined in .travis.yml
build_scripts() {
  if [ ${#CONFIG_BUILD_SCRIPTS[@]} -gt 0 ]; then
    for script in "${CONFIG_BUILD_SCRIPTS[@]}"; do
      arch_msg "Evaluate:\n$(sed 's/^/$ /g'<<<"$script")"
      eval "$script" || exit $?
    done
  else
    echo -e "${ANSI_RED}No build scripts defined${ANSI_RESET}"
    exit 1
  fi
}

install_c_compiler() {
  if [ "$TRAVIS_CC" != "gcc" ]; then
    time_start "Install C Compiler"
    yay -S "$TRAVIS_CC" --noconfirm --needed
    time_stop  "Install C Compiler"
  fi
}

read_config

arch_msg "Setting up Arch environment"
add_repositories

before_install
update_reflector
upgrade_system
install_packages

if [ -n "$CC" ]; then
  install_c_compiler

  # restore CC
  CC=$TRAVIS_CC
  CXX=$TRAVIS_CXX
fi

arch_msg "Running travis build"
build_scripts
