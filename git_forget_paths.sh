#!/usr/bin/env bash


#######################################################################################
#                                                                                     #
#                                 P A R A M E T E R S                                 #
#                                                                                     #
#######################################################################################

# code base to process:
source_url_or_path=https://github.com/Kotlin/kotlin-koans.git

# an arbitrary non-existant local path to use as clone target:
target_local_path=kotlin-koans

# top-level files and/or dirs to keep:
top_level_files_dirs_to_keep=(src build.gradle README.md)

# target git url to push after removing unnecessary paths:
target_remote_url=https://github.com/Kotlin/kotlin-koans-trimmed.git


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
        fi
    done
    echo 0
}

# prints file & dir names in the current working except the specified ones.
# usage: ls_except someDirOrFile anotherDirOrFile ...
ls_except() {
    for item in *; do
        if [ "$(array_contains "${item}" "$@")" == "0" ]; then
            echo $item
        fi
    done
}

# Removes the given paths and related history from the current git repo.
# CAUTION! This may take very long time and rewrites git history!
git_forget_paths() {
    : mirror original branches &&
    git checkout HEAD~0 2>/dev/null &&
    d=$(printf ' %q' "$@") &&
    git for-each-ref --shell --format='
      o=%(refname:short) b=${o#origin/} &&
      if test -n "$b" && test "$b" != HEAD; then
        git branch --force --no-track "$b" "$o"
      fi
    ' refs/remotes/origin/ | sh -e &&
    git checkout - &&
    git remote rm origin &&

    : do the filtering &&
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
    git reflog expire --all && \
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

git clone "$source_url_or_path" "$target_local_path"           &&
(
    cd "$target_local_path"                                    &&

    # if you want to specify files to remove instead of files to keep,
    # use `git_forget_paths` instead of `git_forget_paths_except`:
    git_forget_paths_except ${top_level_files_dirs_to_keep[@]} &&

    # optional clean-up phase
    git_cleanup                                                &&

    # push to new origin
    git remote add origin "$target_remote_url"                 &&
    git_push_all_branches_to_origin
)


#######################################################################################
#                                                                                     #
# REFERENCES:                                                                         #
#                                                                                     #
# - https://stackoverflow.com/a/3910807  - most important parts                       #
# - https://stackoverflow.com/a/26033230                                              #
# - https://stackoverflow.com/a/17864475                                              #
#                                                                                     #
#######################################################################################
