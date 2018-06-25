#!/usr/bin/env bash

# original code base to process (read-only):
source_url_or_path="https://github.com/Kotlin/kotlin-koans.git"

# branch to fetch from remote and append to the local
source_branch="master"

# absolute path to the local repository:
target_path="kotlin-koans"
# Will be created if absent or will be updated if present.
# Note that also these companion paths will be used: $target_path.tmp & $target_path.bak

# top level files and dirs to keep (use names only, not paths!):
top_level_paths_to_keep=(
                         "src"
                         "test"
                         "build.gradle"
                        )

# relative paths to remove after removing everything except $top_level_paths_to_keep:
relative_paths_to_delete=(
                          "src/util"
                          "test/util"
                         )

# tag patterns to delete (use shell patterns possibly including wildcards: *)
tags_to_delete=(
                "some-tag-allowing-wildcards-*"
               )
