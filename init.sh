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
  local old_ifs=$IFS
  IFS=$'\n'
  CONFIG_BEFORE_INSTALL="$(decode_config "${CONFIG_BEFORE_INSTALL}")"
  CONFIG_BUILD_SCRIPTS="$(decode_config "${CONFIG_BUILD_SCRIPTS}")"
  CONFIG_PACKAGES="$(decode_config "${CONFIG_PACKAGES}")"
  CONFIG_REPOS=($(decode_config "${CONFIG_REPOS}"))
  IFS=$old_ifs
}

# add custom repositories to pacman.conf
add_repositories() {
  if [ ${#CONFIG_REPOS[@]} -gt 0 ]; then
    for r in "${CONFIG_REPOS[@]}"; do
      IFS=" " read -r -a splitarr <<< "${r//=/ }"
      ((repo_line+=1))
      sudo sed -i "${repo_line}i[${splitarr[0]}]" /etc/pacman.conf
      ((repo_line+=1))
      sudo sed -i "${repo_line}iServer = ${splitarr[1]}\n" /etc/pacman.conf
      ((repo_line+=1))
    done

    # update repos
    sudo pacman -Syy
  fi
}

# run before_install script defined in .travis.yml
before_install() {
  if [ -n "$CONFIG_BEFORE_INSTALL" ]; then
    bash -xvec "$(bash_ps4); $CONFIG_BEFORE_INSTALL" 2>&1 || exit $?
  fi
}

# upgrade system to avoid partial upgrade states
upgrade_system() {
  sudo pacman -Syu --noconfirm
}

# install packages defined in .travis.yml
install_packages() {
  for package in "${CONFIG_PACKAGES[@]}"; do
    mapfile -t packages <<< "$package"
    yay -S "${packages[@]}" --noconfirm --needed
  done
}

# run build scripts defined in .travis.yml
build_scripts() {
  if [ -n "$CONFIG_BUILD_SCRIPTS" ]; then
    bash -xvec "$(bash_ps4); $CONFIG_BUILD_SCRIPTS" 2>&1 || exit $?
  else
    echo "No build scripts defined"
    exit 1
  fi
}

install_c_compiler() {
  if [ "$TRAVIS_CC" != "gcc" ]; then
    yay -S "$TRAVIS_CC" --noconfirm --needed
  fi
}

arch_msg() {
  lightblue='\033[1;34m'
  reset='\e[0m'
  local args=("$@")
  echo -e "${lightblue}${args[*]}${reset}"
}

read_config

echo "travis_fold:start:arch_travis"
arch_msg "Setting up Arch environment"
add_repositories

before_install
upgrade_system
install_packages

if [ -n "$CC" ]; then
  install_c_compiler

  # restore CC
  CC=$TRAVIS_CC
  CXX=$TRAVIS_CXX
fi
echo "travis_fold:end:arch_travis"
echo ""

arch_msg "Running travis build"
build_scripts
