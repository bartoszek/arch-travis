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

# read value from .travis.yml (separated by new line character)
travis_yml() {
  ruby -ryaml -e 'print ARGV[1..-1].inject(YAML.load(File.read(ARGV[0]))) {|acc, key| acc[key] }.join("\n")' .travis.yml "$@"
}

# read value from .travis.yml (separated by null character)
travis_yml_null() {
  ruby -ryaml -e 'print ARGV[1..-1].inject(YAML.load(File.read(ARGV[0]))) {|acc, key| acc[key] }.join("\0")' .travis.yml "$@"
}

# encode config so it can be passed to docker in an environment var.
encode_config() {
    base64 -w 0 <( if [ "$1" == "--null" ]; then travis_yml_null "${@:2}"; else travis_yml "$@"; fi )
}

# configure docker volumes
configure_volumes() {
    volumes=("$(travis_yml arch mount)")
    [[ -z "${volumes[@]}" ]] && return 1
    # resolve environment variables 
    volumes=($(eval echo ${volumes[@]}))
    # resolve relative paths
    volumes=($(ruby -e "ARGV.each{|vol| puts vol.split(':').map{|path| File.expand_path(path)}.join(':')}" "${volumes[@]}"))
    echo "Docker volumes: ${volumes[@]}" >&2
    printf " -v %s" ${volumes[*]}
}

# read travis config
CONFIG_BEFORE_INSTALL=$(encode_config --null arch before_install)
CONFIG_BUILD_SCRIPTS=$(encode_config --null arch script)
CONFIG_PACKAGES=$(encode_config arch packages)
CONFIG_REPOS=$(encode_config arch repos)
CONFIG_VOLUMES=$(configure_volumes)

mapfile -t envs < <(ruby -e 'ENV.each {|key,_| if not ["PATH","USER","HOME","GOROOT","LC_ALL"].include?(key) then puts "-e #{key}" end}')


docker run --rm \
    -v "$(pwd):/build" \
    ${CONFIG_VOLUMES} \
    -e "CC=$CC" \
    -e "CXX=$CXX" \
    -e CONFIG_BEFORE_INSTALL="$CONFIG_BEFORE_INSTALL" \
    -e CONFIG_BUILD_SCRIPTS="$CONFIG_BUILD_SCRIPTS" \
    -e CONFIG_PACKAGES="$CONFIG_PACKAGES" \
    -e CONFIG_REPOS="$CONFIG_REPOS" \
    "${envs[@]}" \
    bartoszek/arch-travis-bartus:base64
