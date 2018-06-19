# git_forget_paths.sh
Shell script to remove specified paths from a Git repository with the related history.

# Usage
Modify parameters at the top of the file, review the 'SCRIPT' section, and then simply run the script:

- `source_url_or_path`: Location of the source Git repository. This can be a URL of a remote Git repository or a path of a local Git repository path.
- `target_local_path`: Path of a non-existant directory to clone the repository into it.
- `top_level_paths_to_keep`: An array of files and/or directories to keep. All of the other versioned directories and files will be removed.
- `relative_paths_to_delete`: An array of relative paths to delete. You can specify deeper paths like `x/y/z` here.
- `target_remote_url`: URL of an existant Git repository to use as the new origin.

# References
1. https://stackoverflow.com/a/3910807  - most important parts
2. https://stackoverflow.com/a/26033230
3. https://stackoverflow.com/a/17864475
