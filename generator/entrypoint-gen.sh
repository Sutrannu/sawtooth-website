#!/bin/sh
# Copyright (c) 2018 Bitwise IO, Inc.
# Licensed under Creative Commons Attribution 4.0 International License
# https://creativecommons.org/licenses/by/4.0/

readonly wd="/srv/jekyll/"
cd $wd

build_jekyll(){
	rm -rf /srv/jekyll/_site/*
	bundle exec jekyll build --config ./_config.yml
	EXITCODE=$?
}

info(){
    printf "\e[94m%s\e[93m\n" "$1"
}

get_archives(){
    mkdir -p ${wd}archive/
    cd ${wd}archive/
    wget -qNrA gz -nH --no-parent --no-check-certificate \
        http://archive.sawtooth.me/core/
    cd ${wd}archive/core/
    wget -qN --no-check-certificate \
        http://archive.sawtooth.me/core/sl.txt
    cd $wd
}

jenkins_build_url(){
    jburl="https://build.sawtooth.me/job/Sawtooth-Hyperledger/job/"
    jburl="${jburl}sawtooth-${1}/job/${2}/lastSuccessfulBuild/"
    echo -n "$jburl"
}

nightly_epoch(){
    lsb_url="$(jenkins_build_url "$1" "$2")"
    date_str="$(curl -s "$lsb_url" | awk -F '[)(]' '/^\s*\(.*\)$/{print $2}')"
    date -d "$date_str" '+%s' | tr -cd '0-9'
}

info "Generating site with Jekyll"
build_jekyll

info "Retrieving docs"
get_archives

info "Extracting docs"
mkdir -p ./archive/docs
ls ./archive/core/*.gz | xargs -I{} tar --skip-old-files -xzf {} -C ./archive/docs/

info "Retrieving nightlies"
for repo in core seth raft sabre supply-chain; do
    for branch in master; do
        remote_epoch=$(nightly_epoch "$repo" "$branch")
        archive_epoch=$(stat -c '%Y' \
            ./archive/nightly/${repo}/${branch}/html.zip 2>/dev/null \
            || echo 0 | tr -cd '0-9')
        # If the file has not been updated, to not download.
        if [ $remote_epoch -gt $archive_epoch ]; then
            info "  fetching ${repo}/${branch}"
            url="$(jenkins_build_url "$repo" "$branch")artifact/docs/build/html/*zip*/html.zip"
            mkdir -p ./archive/nightly/${repo}/${branch}
            cd ./archive/nightly/${repo}/${branch}
            wget -qN --no-check-certificate "${url}"
            cd $wd
            unzip -qn ./archive/nightly/${repo}/${branch}/html.zip \
                -d ./archive/nightly/${repo}/
            mkdir -p ./archive/docs/${repo}/nightly/${branch}/
            cp -rd ./archive/nightly/${repo}/html/* \
                ./archive/docs/${repo}/nightly/${branch}/
        else
            info "  ${repo}/${branch} up do date"
        fi
    done
done

info "Setting symlinks"
for line in $(cat ${wd}/archive/core/sl.txt); do
    parent=$(echo $line | cut -d: -f1)
    link=$(echo $line | cut -d: -f2)
    target=$(echo $line | cut -d: -f3)
    mkdir -p ${wd}/archive/docs/${parent}
    cd ${wd}/archive/docs/${parent}
    ln -frsT $target $link
done
cd ${wd}

touch jekyll.complete
exit $EXITCODE
