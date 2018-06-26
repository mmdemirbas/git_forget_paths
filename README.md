# git_forget_paths.sh
Shell script to remove specified paths from a Git repository with
the related history.

# Quick Start

1. Prepare a `params.sh` copying from the `sample-params.sh`
2. Run `git_forget_paths.sh params.sh` to create the repository for the
   first time. This may take too long.
3. Run `git_forget_paths.sh params.sh` again to update the existing
   repository from the remote repository whenever you want, and merge
   the created/updated branch manually.


# Usage

## Prepare parameters

Copy `sample-params.sh` as `params.sh` and change per your needs:

- `source_url_or_path`: Location of the source Git repository.
  This can be a URL of a remote Git repository or a path of a local
  Git repository path.
- `source_branch`: Interested remote branch. No other branch will
  be fetched from the remote. Equivalent local branch will be created
  or updated unless it is `master`. In the case of master, always a new
  branch with a name including current date-time will be created such as
  `master-2018-06-25T07-23-35`.
- `target_path`: Path of a non-existant directory to clone
  the repository into it. Note that also `${target_path}.tmp` will be
  created and used for temporary files, and `${target_path}.bak` will be
  created and used to backup current state of the repository before
  update.
- `top_level_paths_to_keep`: An array of top-level files and/or
  directories to keep. You can specify only top-level file/dir names
  here, not paths! CAUTION! All of the other versioned top-level
  directories and files will be removed.
- `relative_paths_to_delete`: An array of relative paths to delete among
  the remaining files (namely `$top_level_paths_to_keep`).
  You can specify deeper relative paths like `x/y/z` here.
- `tags_to_delete`: An array of patterns that match agains the git tags
  to be deleted.

## Run the script

After preparing your `params.sh` file, you can run the script like this:

```
git_forget_paths.sh params.sh
```

This operation may take very long time depending on your repository
size.

At this point, you are done until new changes made to the original
repository.

## Run the script again to update later

After sometime, if development goes on at the original remote
repository, you may want to apply new commits from the original remote
repository into your trimmed local repository.

Whenever you want to update your repository, you can run the script
again in the same manner:

```
git_forget_paths.sh params.sh
```

This will find automatically the commits from both repositories mapping
to each other, by using `commit date + committer email` as key.

After update, new changes will be appended to a branch instead of
the master branch. So, you need to merge the new branch onto your
master manually, if you want.

Note that if `source_branch` is `master`, then a new branch
will be created with the current date-time everytime you try to update,
such as `master-2018-06-25T07-23-35`.

If `source_branch` is not `master`, then a branch with the same
name will be created if doesn't exist or updated if exists.

In the case of unexpected results, you can always rollback previous
state from the backup under `${target_path}.bak`. Each time you run the
script to update your repo, a new backup will be created by the name of
current date-time.
