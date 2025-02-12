## Build Documentation

Ntopng documentation uses read the docs and `.rst` file format. This guide describe how to build the documentation with the latest sphinx version (8.0) instead of the old version (1.8)

## Requirements

On ubuntu:

```
apt-get install doxygen
pip install breathe sphinx sphinx-rtd-theme mock rst2pdf sphinxcontrib.swaggerdoc
````

## Files to update
- conf.py (doc/src/conf.py): 
  - replace line 303 from app.add_stylesheet to app.add_css_file (function changed the name);
  - change line 296 from `intersphinx_mapping = {'https://docs.python.org/': None}` to `intersphinx_mapping = {'python': ('https://docs.python.org/3', None)}`

## Generate

The ntopng documentation can be generated by executing `make html`.

It can be easily tested locally by running a python webserver:

```
  pushd _build/html; python3 -m http.server 8080; popd
```
