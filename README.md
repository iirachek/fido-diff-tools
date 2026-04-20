# fido-diff-tools
Tools to generate diff files between html FIDO specifications.

Depends on [htmldiff-ui](https://github.com/iirachek/htmldiff-ui) from w3c. Put fido-diff-tools scripts into the same folder where `htmldiff.pl` is located.

## Usage
Use `-h` or `--help` to see the usage details.
- `fetch.sh` downloads the previous version of the document specified in the document header. 
- `make_diff.sh` generates a diff between specified files. Works as all-against-all for folders too.

Technically the scripts should work regardless of where they are being called from, but the intended use was to navigate with the terminal into the same directory where the html specifications will be located.