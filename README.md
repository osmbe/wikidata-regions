# wikidata-regions
Using wikidata to create "regions" (groupings of municipalities)

## Status
Currently a POC that shows how to extract safety zones geometries using official geometries & wikidata structure

## Goals
* Create something like https://github.com/provinciesincijfers/gebiedsniveaus, where many "regions" are built that way and both geometries and practical tables are provided.
* Provide some documentation to make it easier to maintain these in Wikidata.
* Build in (more) QA & automation, so that the files are updated weekly, *but* the process is interrupted if unexpected changes occur.
* Add OSM geometry as base (user can switch and choose)

### QA
* compare to official sources where possible
* check if total coverage area is still the expected area
* report when number of objects changes significantly
