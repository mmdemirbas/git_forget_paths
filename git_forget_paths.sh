#!/usr/bin/env bash

########################################################################################################################
#                                                                                                                      #
# PURPOSE:                                                                                                             #
#                                                                                                                      #
# Truncates undesired paths from an existing git repository and deletes the related history.                           #
# This script can be used to extract a new repository out of an existing repository.                                   #
# Resulting repository will not be pushed anywhere, so you need to add a remote origin and push there manually.        #
#                                                                                                                      #
#                                                                                                                      #
# USAGE:                                                                                                               #
#                                                                                                                      #
# Provide a parameters.sh file which defines the required parameters as argument to the script.                        #
#                                                                                                                      #
#                                                                                                                      #
# REFERENCES:                                                                                                          #
#                                                                                                                      #
# - https://stackoverflow.com/a/3910807  - filtering unwanted paths                                                    #
# - https://stackoverflow.com/a/26033230                                                                               #
# - https://stackoverflow.com/a/17864475                                                                               #
# - https://stackoverflow.com/a/42457384 - combining multiple git histories into one                                   #
#                                                                                                                      #
########################################################################################################################

main() {
    prepare_params "$@"
    confirm_params

    if [ ! -d "$target_path" ]; then
        # If target path doesn't exist, use `init` to create a repository for the first time
        init
    else
        # If both the target path and the required commit hash information exist,
        # use `update` to create a branch with the new changes made to the original repository:
        update
    fi
}

prepare_params() {
    # ensure that parameters file specified as an argument
    local params_file=$1
    require_non_empty "$params_file" "<params.sh>"
    [[ ! -e "$params_file" ]] && echo "Params file was missing: $params_file"            && abort
    [[ ! -f "$params_file" ]] && echo "Params file was not a regular file: $params_file" && abort

    # include the parameters file which defines the required variables
    . "$params_file"

    # ensure that the required variables defined in parameters file
    require_non_empty "$source_url_or_path"      "source_url_or_path"
    require_non_empty "$target_path"             "target_path"
    require_non_empty "$top_level_paths_to_keep" "top_level_paths_to_keep"

    # ensure target_path is an absolute path
    target_path="$(realpath "$target_path")"

    # ensure source_branch defined and not empty, or default to master.
    source_branch="${source_branch:-master}"

    [[ -f "$target_path" ]] && echo "Target path was a regular file: $target_path" && abort

    # temporary area to work
    tmp_path="$target_path.tmp"
}

require_non_empty() {
    [[ -z "$1" ]] && echo "$2 should be defined and non-empty" && abort
}

abort() {
    echo
    echo "Aborted. $*" && exit 1
}

success() {
    echo
    echo "[SUCCESS] Completed."
}

confirm_params() {
    [[ ! -d "$target_path" ]] && printf "Create repository at:\n" || printf "Update existing repository at:\n"
    printf "  $target_path\n"
    printf "\n"
    printf "From this source:\n"
    printf "  $source_url_or_path\n"
    printf "\n"
    printf "Branch:\n"
    printf "  $source_branch\n"
    printf "\n"
    printf "Keep only these files:\n"
    printf "  %s\n" "${top_level_paths_to_keep[@]}"
    printf "\n"
    printf "Then delete also these files:\n"
    printf "  %s\n" "${relative_paths_to_delete[@]}"
    printf "\n"
    printf "Then delete tags matching these patterns:\n"
    printf "  %s\n" "${tags_to_delete[@]}"
    printf "\n"
    printf "Note that this operation may take too long depending on your repository size.\n"
    printf "\n"
    printf "Please, review the information above.\n"

    # confirm with typing letter -- don't require to press enter
    read -p "Are you sure? [yN] " -n 1 -r

    # move cursor to a new line
    echo

    # abort unless pressed 'Y' or 'y'
    [[ $REPLY =~ ^[Yy]$ ]] || abort

    echo
}

# clones and truncates a repository for the first time.
# CAUTION: This process may take very long time depending on your repository size!
init() {
    local DATE=`date '+%Y-%m-%d_%H-%M-%S'`
    local tmp="$tmp_path/$DATE"

    git clone "$source_url_or_path" -b "$source_branch" --single-branch "$tmp/$source_branch" || abort
    cd "$tmp/$source_branch" || abort
    git_unlink_origin

    git_delete_tags
    git_truncate_history

    # clone to the target at the end
    git clone "$tmp/$source_branch" "$target_path" || abort
    cd "$target_path"                              || abort
    git_unlink_origin

    # remove temp files
    echo "Cleanup temporary files"
    rm -rf "$tmp"
    rmdir "$tmp_path"

    success
}

# appends updates to the previously initiated repository as a branch
update() {
    local DATE=`date '+%Y-%m-%d_%H-%M-%S'`
    local tmp="$tmp_path/$DATE"
    local newlog="$tmp/.newlog"
    local newkeys="$tmp/.newkeys"
    local oldlog="$tmp/.oldlog"
    local oldkeys="$tmp/.oldkeys"

    mkdir -p "$tmp"                                                                      || abort

    cd "$target_path"                                                                    || abort
    git_log_all                > "$newlog"                                               || abort
    git_log_committer_and_date > "$newkeys"                                              || abort

    # we need only the remote history first, not the code, hence clone with --bare:
    git clone "$source_url_or_path" -b "$source_branch" --single-branch "$tmp/bare" --bare || abort
    cd "$tmp/bare"                                                                       || abort

    git_log_all                > "$oldlog"                                               || abort
    git_log_committer_and_date > "$oldkeys"                                              || abort

    # find latest common commit
    common_commit_key=$(grep --max-count=1 -F -f "$newkeys" "$oldkeys")
    old_commit_line=$(grep "$common_commit_key" "$oldlog")
    new_commit_line=$(grep  "$common_commit_key" "$newlog")
    old_commit_hash=$(echo "$old_commit_line" | cut -d" " -f1)
    new_commit_hash=$(echo "$new_commit_line" | cut -d" " -f1)
    commit_date=$(echo "$new_commit_line" | cut -d" " -f2)
    commit_email=$(echo "$new_commit_line" | cut -d" " -f3)
    commit_msg=$(echo "$new_commit_line" | cut -d" " -f4-9999)

    echo
    echo "Mapping:"
    echo "  Source commit  : $old_commit_hash"
    echo "  Target commit  : $new_commit_hash"
    echo "  Commit date    : $commit_date"
    echo "  Committer mail : $commit_email"
    echo "  Commit message : $commit_msg"
    echo

    # now we need the code only after a known commit:
    # todo: ideal solution --shallow-exclude doesn't work. So we use shallow-since
#    git clone "$source_url_or_path" -b "$source_branch" --single-branch "$tmp/truncated" --shallow-exclude="$old_commit_hash" || abort
    git clone "$source_url_or_path" -b "$source_branch" --single-branch "$tmp/truncated" --shallow-since="$commit_date" || abort
    cd "$tmp/truncated"                                                                  || abort
    git_unlink_origin
    git_delete_tags
    git_forget_history_including "$old_commit_hash"
    git_truncate_history

    # re-cloning generally reduces the repo size
    git clone "$tmp/truncated" "$tmp/truncated-recloned"                                 || abort

    # Create backup
    local backup_path="$target_path.bak"
    echo "Creating backup at $backup_path/$DATE"
    mkdir -p "$backup_path"                                                              || abort
    cp -R "$target_path" "$backup_path/$DATE"                                            || abort

    # go back to the graft point of the initial repo and start a branch there
    echo "Stashing any change in target repository before update"
    cd "$target_path"                                                                    || abort
    git stash                                                                            || abort

    if [[ "$source_branch" = "master" ]]; then
        git checkout -b "master-$DATE"                                                   || abort
    else
        # -B: create new or checkout existing
        git checkout -B "$source_branch"                                                 || abort
    fi

    # obtain new changes and append to the history of the branch
    remote_name="$DATE"
    remote_branch="$remote_name/$source_branch"
    git remote add "$remote_name" "$tmp/truncated-recloned"                              || abort
    git fetch "$remote_name"                                                             || abort

    # usage: git replace [-f] --graft <commit> [<parent>...]
    echo
    echo "Updating by rewriting history"
    git reset --hard "$new_commit_hash"                                                  || abort
    git replace --graft $(git_first_commit_hash "$remote_branch") HEAD                   || abort
    git reset --hard "$remote_branch"                                                    || abort
    git_delete_backups
    git remote rm "$remote_name"

    echo "Unstashing changes stashed before update"
    git stash pop

    # remove temp files
    echo "Cleanup temporary files"
    rm -rf "$tmp"
    rmdir "$tmp_path"

    success
}

git_log_all() {
    # %H: long commit hash
    # %h: long commit hash
    # %cI: committer date-time
    # %ce: committer e-mail
    # %s: commit message
    git --no-pager log --pretty=format:'%C(yellow)%H %C(cyan)%cI %C(red)%ce %C(reset)%s' --all || abort
}

git_log_committer_and_date() {
    # %cI: committer date-time
    # %ce: committer e-mail
    git --no-pager log --pretty=format:'%C(cyan)%cI %C(red)%ce' --all || abort
}

# Removes the given paths and related history from the current git repo.
# CAUTION! This may take very long time and rewrites git history!
git_truncate_history(){
    # use a temp file to prevent 'Argument line too long' error
    local tmp=$(realpath ".paths-to-forget.tmp")
    ls_except "${top_level_paths_to_keep[@]}"  > "$tmp"
    echo "${relative_paths_to_delete[@]}"     >> "$tmp"

    echo
    echo "Files to delete (if exist):"
    echo
    cat "$tmp" | xargs -n 1 printf "  %s\n"
    echo

    git filter-branch --index-filter "cat \"$tmp\" | xargs git rm --ignore-unmatch --cached -r --" \
        --tag-name-filter cat --prune-empty -- --all || abort

    git_delete_backups
    git_cleanup
    rm "$tmp"
}

git_forget_history_including() {
    git filter-branch --parent-filter "sed \"s/-p $1[0-9a-f]*//\"" --tag-name-filter cat --prune-empty -- --all  || abort
    git_delete_backups
}

# lists top-level files & dirs, ignoring the specified paths.
# usage: ls_except someRelativePath anotherRelativePath ...
ls_except() {
    for item in $(ls -A); do
        [[ "$(is_excluded_path "${item}" "$@")" == "0" ]] && echo "$item"
    done
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

git_delete_tags(){
    git tag --list "${tags_to_delete[@]}" | xargs git tag -d  || abort
    git_cleanup
}

git_cleanup() {
    git reflog expire --all --expire-unreachable=0
    git gc --aggressive --prune=now
    git repack -A -d
    git prune
}

git_delete_backups() {
    rm -rf .git/refs/original
}

git_first_commit_hash() {
    git log "$1" --format=%H | tail -1 || abort
}

git_unlink_origin() {
    git remote rm origin
}

main "$@"
