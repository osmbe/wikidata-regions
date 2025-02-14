## ---------------------------
##
## Script name: Create a topologically sound municipality layer ----
##
## Purpose of script: Download official municipality boundaries, fix geometry issues and save as local file
##
## Author: Joost Schouppe
##
## Date Created: 2025-02-04
##
##
## ---------------------------

# Set environment variables
#readRenviron("C:/projects/pgn-data-airflow/.Renviron")
temporary_folder <-Sys.getenv("TEMPORARY_STORAGE")

# Load libraries
library(sf)
library(dplyr)
library(units)

# EXTRACT ------------------------------------------------

## Download municipality official data
# portal: https://financien.belgium.be/nl/experten-partners/open-patrimoniumdata/datasets/downloadportaal
# check if there is a new version on the portal

# download zip
# set the source
zip_url<-"https://opendata.fin.belgium.be/download/datasets/AU-RefSit_20250113_shp_31370_01000.zip"
# set the location to save it
local_zip_path <- paste0(temporary_folder,"/municipality.zip")
# Download the ZIP file
GET(url = zip_url, write_disk(local_zip_path, overwrite = TRUE))
# Unzip the downloaded file
unzip(local_zip_path, exdir = temporary_folder)

# open the shapefile 
municipal_geometry <- st_read(paste0(temporary_folder,"/CADGIS.Apn_AdMu.shp"))
#plot(municipal_geometry$geometry)

# set all columns to lowercase
municipal_geometry <- municipal_geometry %>% 
  rename_all(tolower) %>%
  select(NIS_INS=admukey)

# set NIS_INS to numeric
municipal_geometry$NIS_INS <- as.numeric(municipal_geometry$NIS_INS)

# TRANSFORM ------------------------------------------------

# The data has small issues: they are not perfectly topologically sound. st_snap can fix all the issues, howover it is very slow when run on the entire dataset. To avoid unneeded calculations, we first select just the munipalities that actually have issues.

## FIND SMALL GAPS ----

# Merge into a single polygon (which exposes all the issues)
municipalities_aggregated <- municipal_geometry %>%
  summarize(geometry = st_union(geometry), .groups = "drop") %>%
  mutate(geometry = st_make_valid(geometry))  # Fix invalid geometries

# Split into individual polygons
components <- st_cast(municipalities_aggregated, "POLYGON") %>%
  mutate(area = st_area(geometry))

# Convert to MULTILINESTRING to extract boundaries & interior rings
multi_lines <- st_cast(components, "MULTILINESTRING")

# Convert to individual LINESTRINGs
line_parts <- st_cast(multi_lines, "LINESTRING")

# calculate area 
holes <- holes %>%
  mutate(area = st_area(geometry))

# convert area to numeric without unit
holes$area <- as.numeric(holes$area)


# Filter small holes < 1 m²
tiny_holes <- holes %>%
  filter(area < 1)
plot(tiny_holes$geometry)
tiny_holes$tiny_hole=TRUE
tiny_holes<-tiny_holes %>% select(tiny_hole)

# Spatial join
holes_with_municipalities <- st_join(tiny_holes, municipal_geometry, left = FALSE)

# as data frame list the NIS_INS codes
municipalities_with_holes <- as.data.frame(holes_with_municipalities) %>%
  group_by(NIS_INS) %>%
  summarize(tiny_hole = any(tiny_hole), .groups = "drop")

# left join to municipalities
municipal_geometry <- left_join(municipal_geometry, municipalities_with_holes, by = "NIS_INS")


## FIND SMALL OVERLAPS ----
municipal_geometry <- municipal_geometry %>%
  mutate(overlaps = ifelse(!st_is_valid(geometry) | 
                                lengths(st_overlaps(geometry, municipal_geometry)) > 0, 
                              TRUE, 
                              FALSE))

# check the result
perfect_polygons <- municipal_geometry %>% filter((is.na(overlaps) | overlaps==FALSE) & (is.na(tiny_hole) | tiny_hole==FALSE))
municipalities_aggregated <- perfect_polygons %>%
  summarize(geometry = st_union(geometry), .groups = "drop")
plot(municipalities_aggregated$geometry)

## FILTER & FIX THE CASES WITH ISSUES ----
imperfect_polygons <- municipal_geometry %>% filter(overlaps==TRUE | tiny_hole==TRUE)

# snap gaps of less than a meter
imperfect_polygons <- imperfect_polygons %>%
  mutate(geometry = st_snap(geometry, geometry, tolerance = 1))

# Fix newly invalid geometries
imperfect_polygons <- imperfect_polygons %>%
  mutate(geometry = st_make_valid(geometry))


## MERGE TO REST OF THE DATA ----
municipal_geometry_cleaned <- rbind(perfect_polygons, imperfect_polygons)

# check the result
municipalities_aggregated <- municipal_geometry_cleaned %>%
  summarize(geometry = st_union(geometry), .groups = "drop")
plot(municipalities_aggregated$geometry)

municipal_geometry_cleaned <- municipal_geometry_cleaned %>% select(-overlaps, -tiny_hole)

# LOAD ------------------------------------------------

# Save the cleaned data
st_write(municipal_geometry_cleaned, paste0(temporary_folder,"/municipalities_cleaned.gpkg"), append=FALSE)
