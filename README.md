# git_forget_paths.sh
Shell script to remove specified paths from a Git repository with the related history.

# Quick Start

1. Prepare a `params.sh` copying from the `sample-params.sh`
2. Run `git_forget_paths.sh params.sh` to create the repository first time.
3. Run `git_forget_paths.sh params.sh` againg to update the existing repository from the remote repository whenever you want.

# Usage

## Prepare parameters

Copy `sample-params.sh` as `params.sh` and change per your needs:

- `source_url_or_path`: Location of the source Git repository. This can be a URL of a remote Git repository or a path of a local Git repository path.
- `target_path`: Path of a non-existant directory to clone the repository into it. Note that `${target_path}.tmp` will be created and used for temporary files, and `${target_path}.bak` will be created and used to backup current state of the repository before modifications.
- `top_level_paths_to_keep`: An array of top-level files and/or directories to keep. You can specify only top-level file/dir names here, not paths! CAUTION! All of the other versioned top-level directories and files will be removed.
- `relative_paths_to_delete`: An array of relative paths to delete among the remaining files (`top_level_paths_to_keep`). You can specify deeper relative paths like `x/y/z` here.
- `tags_to_delete`: An array of patterns that match agains the git tags to be deleted.

## Run script for the first time

After preparing your `params.sh` file, you can run the script like this:

```
git_forget_paths.sh params.sh
```

This operation may take very long time depending on your repository size. After completion, you have a folder structure similar to the following:

```
src
test
build.gradle
.last_commit_old_hash
.last_commit_new_hash
```

At this point, you are done.

## Run script again later

After sometime, if development goes on at the original remote repository, you may want to apply new commits from the original remote repository into your trimmed local repository.

Whenever you want to update your repository, you can run the script again in the same manner:

```
git_forget_paths.sh params.sh
```

Note that the new changes will be appended to an automatically created branch instead of the master branch. So, you need to perform following operations manually:

1. Rebase the new branch onto your master branch.
2. Merge the new branch onto your master branch.

#### How updating works?
To enable updating, we need to know the latest commit hashes from the both repositories mapping to each other. We store this information in the following extra files:

```
.last_commit_old_hash
.last_commit_new_hash
```

As the local repository exists, the script knows that you want to update the existing repository and uses the commit hash information to update automatically.


# References
1. https://stackoverflow.com/a/3910807  - filtering unwanted paths
2. https://stackoverflow.com/a/26033230
3. https://stackoverflow.com/a/17864475
4. https://stackoverflow.com/a/42457384 - combining multiple git histories into one
