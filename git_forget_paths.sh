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
########################################################################################################################

main() {
    prepare_params "$@"
    confirm_params

    # If target path doesn't exist, use `init` to create a repository for the first time.
    # Otherwise, use `update` to apply new changes made to the original repository.
    [[ ! -d "$target_path" ]] && init || update
}

prepare_params() {
    # ensure that parameters file specified as an argument
    local params_file=$1
    require_non_empty "$params_file" "<params.sh>"
    [[ ! -e "$params_file" ]] && abort "Params file was missing: $params_file"
    [[ ! -f "$params_file" ]] && abort "Params file was not a regular file: $params_file"

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

    [[ -f "$target_path" ]] && abort "Target path was a regular file: $target_path"

    # temporary area to work
    tmp_path="$target_path.tmp"
}

require_non_empty() {
    [[ -z "$1" ]] && abort "$2 should be defined and non-empty"
}

abort() {
    echo
    echo "[FAILURE] Aborted. $*" && exit 1
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
    printf "And delete tags matching these patterns:\n"
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
    [[ $REPLY =~ ^[Yy]$ ]] || abort "User cancelled."

    echo
}

# clones and truncates a repository for the first time.
# CAUTION: This process may take very long time depending on your repository size!
init() {
    local DATE=`date '+%Y-%m-%d_%H-%M-%S'`
    local tmp="$tmp_path/$DATE"

    git clone "$source_url_or_path" -b "$source_branch" --single-branch "$tmp/$source_branch" || abort "Clone failed: $source_url_or_path"
    cd "$tmp/$source_branch" || abort "Couldn't cd into $tmp/$source_branch"
    git_truncate_history

    # clone to the target at the end
    git clone "$tmp/$source_branch" "$target_path" || abort "Clone failed: $tmp/$source_branch"
    cd "$target_path"                              || abort "Couldn't cd into $target_path"
    git_unlink_origin

    # remove temp files
    echo "Cleanup temporary files..."
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
    local bare="$tmp/bare"
    local truncated="$tmp/truncated"
    local recloned="$tmp/truncated-recloned"

    mkdir -p "$tmp"                                                                         || abort "Couldn't create $tmp"

    # we need only the remote history first, not the code, hence clone with --bare:
    git clone "$source_url_or_path" -b "$source_branch" --single-branch "$bare" --bare      || abort "Clone failed: $source_url_or_path"
    cd "$bare"                                                                              || abort "Couldn't cd into $bare"

    git_log_all                "$source_branch" > "$oldlog"
    git_log_committer_and_date "$source_branch" > "$oldkeys"

    cd "$target_path"                                                                       || abort "Couldn't cd into $target_path"
    git_log_all                                 > "$newlog"
    git_log_committer_and_date                  > "$newkeys"

    # find latest common commit
    common_commit_key=$(grep --max-count=1 -F -f "$newkeys" "$oldkeys")
    old_commit_line=$(grep --max-count=1 "$common_commit_key" "$oldlog")
    new_commit_line=$(grep --max-count=1 "$common_commit_key" "$newlog")
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
    require_non_empty "$common_commit_key" "No common commit found! common_commit_key"

    # now we need the code only after a known commit:
#    git clone "$source_url_or_path" -b "$source_branch" --single-branch "$truncated" --shallow-exclude="$old_commit_hash" || abort
    git clone "$source_url_or_path" -b "$source_branch" --single-branch "$truncated" --shallow-since="$commit_date" || abort "Clone failed: $source_url_or_path"
    cd "$truncated"                                                                           || abort "Couldn't cd into $truncated"
    git_truncate_history

    # re-cloning generally reduces the repo size
    git clone "$truncated" "$recloned"                                                        || abort "Clone failed: $truncated"

    # Create backup
    local backup_parent_path="$target_path.bak"
    local backup_path="$backup_parent_path/$DATE"
    echo "Creating backup at \"$backup_path\"..."
    mkdir -p "$backup_parent_path" && cp -R "$target_path" "$backup_path" || abort "Backup failed! Path: $backup_path"

    # go back to the graft point of the initial repo and start a branch there
    echo "Stashing any change in target repository before update..."
    cd "$target_path"                                                                         || abort "Couldn't cd into $target_path"
    git stash                                                                                 || abort "git stash failed!"

    # obtain new changes and append to the history of the branch
    remote_name="$DATE"
    remote_branch="$remote_name/$source_branch"
    git remote add "$remote_name" "$recloned" || abort "Couldn't add remote: $recloned"
    git fetch "$remote_name"                  || abort "Couldn't fetch remote: $remote_name"

    # create new branch if source_branch is master
    local target_branch=$([ "$source_branch" = "master" ] && echo "master-$DATE" || echo "$source_branch")
    # -B: create new or checkout existing
    git checkout -B "$target_branch" || abort "\`git checkout \"$target_branch\"\` failed!"

    local effective_old_commit_hash="$(git log "$remote_branch" --format="%H" | tail -1 || abort "Couldn't get git log!")"
    require_non_empty "$effective_old_commit_hash" "No new commit! effective_old_commit_hash"

    # report changes will be made
    echo
    echo "New commits:"
    git --no-pager log "$remote_name/$source_branch" --pretty="format:%C(auto)%x09%h %C(magenta)%>(27)%ce %C(cyan)%cI %C(dim cyan)%<(15)%cr %C(auto)%d %C(auto)%s%C(reset)" --graph
    echo

    # usage: git replace [-f] --graft <commit> [<parent>...]
    echo
    echo "Rewriting history..."
    git filter-branch --parent-filter "sed \"s/-p ${effective_old_commit_hash}[0-9a-f]*/-p $new_commit_hash/\""  \
        --tag-name-filter cat --prune-empty -- --all          || abort "Failed to replace $effective_old_commit_hash with $new_commit_hash"
    git reset --hard "$remote_branch"                         || abort "Failed to hard reset to HEAD of $remote_branch!"
    git remote rm "$remote_name"
    git_delete_backups
    git_cleanup

    echo "Unstashing changes stashed before update..."
    git stash pop

    # remove temp files
    echo "Cleanup temporary files..."
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
    git --no-pager log --pretty=format:'%C(yellow)%H %C(cyan)%cI %C(red)%ce %C(reset)%s' "${1:---all}" || abort "Couldn't get git log!"
}

git_log_committer_and_date() {
    # %cI: committer date-time
    # %ce: committer e-mail
    git --no-pager log --pretty=format:'%C(cyan)%cI %C(red)%ce' "${1:---all}" || abort "Couldn't get git log!"
}

# Removes the given paths and related history from the current git repo.
# CAUTION! This may take very long time and rewrites git history!
git_truncate_history() {
    git_unlink_origin
    git_delete_tags

    # use a temp file to prevent 'Argument line too long' error
    local tmp=$(realpath ".paths-to-forget.tmp")
    ls_except "${top_level_paths_to_keep[@]}" ".git"  > "$tmp"
    echo "${relative_paths_to_delete[@]}"            >> "$tmp"

    echo
    echo "Files to delete (if exist & versioned):"
    echo
    cat "$tmp" | xargs -n 1 printf "  %s\n"
    echo

    git filter-branch --index-filter "cat \"$tmp\" | xargs git rm --ignore-unmatch --cached -r --" \
        --tag-name-filter cat --prune-empty -- --all || abort "Couldn't truncate selected paths from the history!"

    git_delete_backups
    git_cleanup
    rm "$tmp"
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
    git tag --list "${tags_to_delete[@]}" | xargs git tag -d  || abort "Couldn't delete git tags!"
    git_cleanup
}

git_cleanup() {
    # Prune all unreachable objects from the object database
    git gc --aggressive --prune=now
    git reflog expire --expire-unreachable=0 --verbose --stale-fix --expire=now --all
    git repack -A -d
}

git_delete_backups() {
    rm -rf .git/refs/original
}

git_unlink_origin() {
    git remote rm origin
}

main "$@"
