#!/usr/bin/env bash


echo "[WARN] Are you sure?"
echo "[WARN] Ensure that you change the PARAMETERS section per your needs and uncomment necessary lines in the SCRIPT section."
echo "[WARN] Afterwards, you can comment out this line to run script." && exit 1


#######################################################################################
#                                                                                     #
#                                 P A R A M E T E R S                                 #
#                                                                                     #
#######################################################################################

# code base to process:
source_url_or_path=https://github.com/Kotlin/kotlin-koans.git

# an arbitrary non-existant local path to use as clone target:
target_local_path=kotlin-koans

# top level files and dirs to keep. to be passed to `git_forget_paths_except` function:
top_level_paths_to_keep=(
                         "src"
                         "test"
                         ".gitignore"
                         "build.gradle"
                         )

# relative paths to remove. to be passed to `git_forget_paths` function:
relative_paths_to_delete=(
                          "gradle/wrapper"
                          "gradlew"
                          "gradlew.bat"
                          "test/util"
                          ".idea/runConfigurations/x.xml"
                          ".idea/runConfigurations/y.xml"
                          ".idea/runConfigurations/z.xml"
                         )

# tag patterns to delete (shell patterns using wildcard)
tags_to_delete=(
                "*xxx*"
                "*yyy*"
                "*zzz*"
              )

# target git url to push after removing unnecessary paths:
target_remote_url=https://github.com/Kotlin/kotlin-koans-destructed.git


#######################################################################################
#                                                                                     #
#                                  F U N C T I O N S                                  #
#                                                                                     #
#######################################################################################

# checks whether a given array contains the specified element.
# usage: array_contains element-to-find array-items...
array_contains() {
    local needle=$1
    shift 1
    for i in $@; do
        if [[ $i == $needle ]]; then
            echo 1
            return
        fi
    done
    echo 0
}

# prints file & dir names in the current working except the specified ones.
# usage: ls_except someDirOrFile anotherDirOrFile ...
ls_except() {
    for item in $(ls -A); do
        if [ "$(array_contains "${item}" "$@")" == "0" ]; then
            echo $item
        fi
    done
}

# Removes the given paths and related history from the current git repo.
# CAUTION! This may take very long time and rewrites git history!
git_forget_paths() {
    : mirror original branches                       &&
    git checkout HEAD~0 2>/dev/null                  &&
    d=$(printf ' %q' "$@")                           &&
    git for-each-ref --shell --format='
      o=%(refname:short) b=${o#origin/} &&
      if test -n "$b" && test "$b" != HEAD; then
        git branch --force --no-track "$b" "$o"
      fi
    ' refs/remotes/origin/ | sh -e                   &&
    git checkout -                                   &&
    git remote rm origin

    : do the filtering                               &&
    git filter-branch \
      --index-filter 'git rm --ignore-unmatch --cached -r -- '"$d" \
      --tag-name-filter cat \
      --prune-empty \
      -- --all
}

# Removes all paths EXCEPT the given ones and related history from the current git repo.
# CAUTION! This may take very long time and rewrites git history!
git_forget_paths_except() {
    git_forget_paths $(ls_except "$@")
}

# Performs some house-keeping tasks on the current git repo.
git_cleanup() {
    git reflog expire --all &&
    git gc --aggressive --prune=now
    git reflog expire --all --expire-unreachable=0
    git repack -A -d
    git prune
}

# Runs git push command for each local branch of the current git repo.
git_push_all_branches_to_origin() {
    git push origin master

    for branch in `git branch | grep -v '\*'`
    do
        git push origin $branch
    done
}


#######################################################################################
#                                                                                     #
#                                      S C R I P T                                    #
#                                                                                     #
#######################################################################################

#git clone "$source_url_or_path" "$target_local_path"           &&
#(
#    cd "$target_local_path"                                    &&
#
#    ## if you want to specify files to remove instead of files to keep,
#    ## use `git_forget_paths` instead of `git_forget_paths_except`:
#    #git_forget_paths_except ${top_level_paths_to_keep[@]}       &&
#    #git_forget_paths ${relative_paths_to_delete[@]}            &&
#
#    ## optional clean-up phase
#    #git_cleanup                                                &&
#
#    ## remove unnecessary tags
#    #git tag --list ${tags_to_delete[@]} | xargs git tag -d     &&
#
#    ## push to new origin
#    #git remote add origin "$target_remote_url"                 &&
#    #git_push_all_branches_to_origin                            &&
#   :
#)

#######################################################################################
#                                                                                     #
# REFERENCES:                                                                         #
#                                                                                     #
# - https://stackoverflow.com/a/3910807  - most important parts                       #
# - https://stackoverflow.com/a/26033230                                              #
# - https://stackoverflow.com/a/17864475                                              #
#                                                                                     #
#######################################################################################
