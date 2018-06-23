#!/usr/bin/env bash

########################################################################################################################
#                                                                                                                      #
# AIM:                                                                                                                 #
#                                                                                                                      #
# Truncates undesired paths from an existing git repository and deletes the related history.                           #
# This script can be used to extract a new repository out of an existing repository.                                   #
# Resulting repository will not be pushed anywhere, so you need to add a remote origin and push there manually.        #
#                                                                                                                      #
#                                                                                                                      #
# USAGE:                                                                                                               #
#                                                                                                                      #
# Provide a parameters .sh file which defines the required parameters as argument to the script.                       #
#                                                                                                                      #
########################################################################################################################

# ensure that parameters file specified as an argument
if [[   -z "$1" ]]; then echo "Please, provide the parameters file as argument."; abort; fi
if [[ ! -e "$1" ]]; then echo "Params file was missing: $1"                     ; abort; fi
if [[ ! -f "$1" ]]; then echo "Params file was not a regular file: $1"          ; abort; fi

# include the parameters file which defines the required variables
. "$1"

# ensure that the required variables defined in parameters file
if [ -z "$source_url_or_path"      ]; then echo "source_url_or_path not defined"              ; abort; fi
if [ -z "$target_path"             ]; then echo "target_path not defined"                     ; abort; fi
if [ -z "$top_level_paths_to_keep" ]; then echo "top_level_paths_to_keep not defined"         ; abort; fi

# ensure target_path is an absolute path
target_path=$(realpath "$target_path")

if [ -f "$target_path" ]; then echo "Target path was a regular file: $target_path"; abort; fi

# internally used file names (no need to change these):
tmp_path="$target_path.tmp"
backup_path="$target_path.bak"
last_commit_old_hash_file="$target_path/.last_commit_old_hash"
last_commit_new_hash_file="$target_path/.last_commit_new_hash"

########################################################################################################################
#                                                                                                                      #
#                                              F U N C T I O N S                                                       #
#                                                                                                                      #
########################################################################################################################

abort() {
    echo "Aborted."
    exit 1
}

check_params() {
    if [ "$#" -eq "0" ]; then
        printf "  Will create repository at:\n"
        printf "    $target_path\n"
        printf "\n"
        printf "  From this source:\n"
        printf "    $source_url_or_path\n"
        printf "\n"
        printf "  Keep only these files:\n"
        printf "    %s\n" "${top_level_paths_to_keep[@]}"
        printf "\n"

        printf "  Then delete also these files:\n"
        printf "    %s\n" "${relative_paths_to_delete[@]}"
        printf "\n"

        printf "  Then delete tags matching these patterns:\n"
        printf "    %s\n" "${tags_to_delete[@]}"
    else
        printf "  Will update existing repository at:\n"
        printf "    $target_path\n"
        printf "\n"
        printf "  From this source:\n"
        printf "    $source_url_or_path\n"
        printf "\n"
        printf "  Mapping these commits:\n"
        printf "    Commit at original remote repository: $1\n"
        printf "    Commit at existing local repository : $2\n"
        printf "\n"
        printf "  Keep only these files:\n"
        printf "    %s\n" "${top_level_paths_to_keep[@]}"
        printf "\n"

        printf "  Then delete also these files:\n"
        printf "    %s\n" "${relative_paths_to_delete[@]}"
        printf "\n"

        printf "  Then delete tags matching these patterns:\n"
        printf "    %s\n" "${tags_to_delete[@]}"
    fi

    printf "\n"
    printf "  Note that this operation may take too long depending on your repository size.\n"
    printf "\n"
    printf "Please, review the information above.\n"


    # confirm with typing letter -- don't require to press enter
    read -p "Are you sure? [yN] " -n 1 -r

    # move cursor to a new line
    echo

    # abort unless pressed 'Y' or 'y'
    [[ $REPLY =~ ^[Yy]$ ]] || abort
}

# checks whether a given array contains the specified element.
# usage: is_excluded_path element-to-find array-items...
is_excluded_path() {
    local path=$1
    shift 1
    for excluded in "$@"; do
        [[ "$path" == "$excluded" ]] || [[ "${path}" =~ ^${excluded} ]] && echo 1 && return
    done
    echo 0
}

# lists top-level files & dirs, ignoring the specified paths.
# usage: ls_except someRelativePath anotherRelativePath ...
ls_except() {
    for item in $(ls -A); do
        if [ "$(is_excluded_path "${item}" "$@")" == "0" ]; then
            echo $item
        fi
    done
}

git_delete_tags(){
    git tag --list "${tags_to_delete[@]}" | xargs git tag -d
}

git_delete_backups() {
    rm -rf .git/refs/original
}

git_forget_history_including() {
    git filter-branch \
        --parent-filter "sed \"s/-p $1[0-9a-f]*//\"" \
        --prune-empty \
        -- --all

    git_delete_backups
}

# Removes the given paths and related history from the current git repo.
# CAUTION! This may take very long time and rewrites git history!
git_forget_paths() {
    # use a temp file to prevent 'Argument line too long' error
    local tmp_paths=$(realpath ".paths-to-forget.tmp")
    printf "%q " "$@" > "$tmp_paths"

    git filter-branch \
      --index-filter "cat '$tmp_paths' | xargs git rm --ignore-unmatch --cached -r --" \
      --tag-name-filter cat \
      --prune-empty \
      -- --all

    git_delete_backups
    rm "$tmp_paths"
}

git_truncate_history(){
  git_forget_paths $(ls_except "${top_level_paths_to_keep[@]}")
  git_forget_paths "${relative_paths_to_delete[@]}"
}

# Performs some house-keeping tasks on the current git repo.
git_cleanup() {
    git reflog expire --all &&
    git gc --aggressive --prune=now
    git reflog expire --all --expire-unreachable=0
    git repack -A -d
    git prune
}

git_first_commit_hash() {
    git log "${1:-master}" --format=%H | tail -1
}

git_last_commit_hash() {
    git log "${1:-master}" --format=%H | head -1
}

git_last_commit_time() {
    git show "${1:-master}" -s --format=%ci HEAD
}

# clones and truncates a repository for the first time.
# CAUTION: This process may take very long (hours) depending on your repository size!
initiate() {
    local DATE=`date '+%Y-%m-%d_%H-%M-%S'`
    local tmp="$tmp_path/$DATE"

    git clone "$source_url_or_path" "$tmp/0"                                                                          &&
    cd "$tmp/0"                                                                                                       &&

    # note the old hash to use later in 'update' method
    local last_commit_old_hash=$(git_last_commit_hash)                                                                &&

    # remove redundancy
    git_delete_tags                                                                                                   &&
    git_cleanup                                                                                                       &&
    git remote rm origin                                                                                              &&
    git_truncate_history                                                                                              &&
    git_cleanup                                                                                                       &&

    # re-cloning generally reduces the repo size
    cd -                                                                                                              &&
    git clone "$tmp/0" "$tmp/1"                                                                                       &&

    # clone to the target at the end
    git clone "$tmp/1" "$target_path"                                                                                 &&
    cd "$target_path"                                                                                                 &&
    git remote rm origin                                                                                              &&

    # note the new hash to use later in 'update' method
    local last_commit_new_hash=$(git_last_commit_hash)                                                                &&
    cd -                                                                                                              &&

    # save noted commit hashes
    echo "$last_commit_old_hash" > "$last_commit_old_hash_file"                                                       &&
    echo "$last_commit_new_hash" > "$last_commit_new_hash_file"                                                       &&

    # remove temp files
    rm -rf "$tmp"                                                                                                     &&
    rmdir "$tmp_path"                                                                                                 &&
    :
}

# appends updates to the previously initiated repository as a branch
update() {
    local DATE=`date '+%Y-%m-%d_%H-%M-%S'`
    local tmp="$tmp_path/$DATE"

    # detect latest commit date to shorten cloning process
    cd "$target_path"                                                                                                 &&
    local last_commit_time=$(git_last_commit_time)                                                                    &&
    cd -                                                                                                              &&

    # clone remote repo after the last processed commit
    echo "Cloning the original repo changes after $last_commit_time"                                                  &&
    git clone "$source_url_or_path" "$tmp/0" --shallow-since="$last_commit_time"                                      &&
    cd "$tmp/0"                                                                                                       &&

    # note the old hash to update previously noted one at the end
    local last_commit_old_hash=$(git_last_commit_hash)                                                                &&

    # remove redundancy
    git_delete_tags                                                                                                   &&
    git_cleanup                                                                                                       &&
    git remote rm origin                                                                                              &&
    git_forget_history_including "$(head -1 "$last_commit_old_hash_file")"                                            &&
    git_truncate_history                                                                                              &&
    git_cleanup                                                                                                       &&

    # re-cloning generally reduces the repo size
    cd -                                                                                                              &&
    git clone "$tmp/0" "$tmp/1"                                                                                       &&

    # note the new hash to update previously noted one at the end
    cd "$tmp/1"                                                                                                       &&
    local last_commit_new_hash=$(git_last_commit_hash)                                                                &&
    cd -                                                                                                              &&

    # Create backup
    echo "Creating backup at $backup_path/$DATE"                                                                      &&
    mkdir -p "$backup_path"                                                                                           &&
    cp -R "$target_path" "$backup_path/$DATE"                                                                         &&

    # go to the initial repo
    cd "$target_path"                                                                                                 &&

    # go back to the graft point and start a branch from there
    git stash
    git checkout $(head -1 "$last_commit_new_hash_file")                                                              &&
    git checkout -b "$DATE"                                                                                           &&

    # obtain new changes and append to the history of the branch
    remote_name="$DATE"
    remote_branch="$remote_name/master"                                                                               &&
    git remote add "$remote_name" "$tmp/1"                                                                            &&
    git fetch --all                                                                                                   &&
    # git replace [-f] --graft <commit> [<parent>...]
    git replace --graft $(git_first_commit_hash "$remote_branch") HEAD                                                &&
    git reset --hard "$remote_branch"                                                                                 &&
    git_delete_backups                                                                                                &&
    git remote rm "$remote_name"                                                                                      &&

    # back to the starting directory
    cd -                                                                                                              &&

    # update noted commit hashes
    echo "$last_commit_old_hash" > "$last_commit_old_hash_file"                                                       &&
    echo "$last_commit_new_hash" > "$last_commit_new_hash_file"                                                       &&

    # remove temp files
    rm -rf "$tmp"                                                                                                     &&
    rmdir "$tmp_path"                                                                                                 &&
    :
}


if [ ! -d "$target_path" ]
then
    # If target path doesn't exist, use `initiate` to create a repository for the first time
    check_params
    initiate

elif [ ! -f "$last_commit_old_hash_file" ] || [ ! -f "$last_commit_new_hash_file" ]
then
    echo "Following files must exist to update the repository:"
    echo "  $last_commit_old_hash_file"
    echo "  $last_commit_new_hash_file"
    abort

else
    # If both the target path and the required commit hash information exist,
    # use `update` to create a branch with the new changes made to the original repository:
    check_params $(head -1 "$last_commit_old_hash_file") $(head -1 "$last_commit_new_hash_file")
    update
fi

########################################################################################################################
#                                                                                                                      #
# REFERENCES:                                                                                                          #
#                                                                                                                      #
# - https://stackoverflow.com/a/3910807  - filtering unwanted paths                                                    #
# - https://stackoverflow.com/a/26033230                                                                               #
# - https://stackoverflow.com/a/17864475                                                                               #
# - https://stackoverflow.com/a/42457384 - combining multiple git histories into one                                   #
#                                                                                                                      #
########################################################################################################################
