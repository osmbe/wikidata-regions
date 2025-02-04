## ---------------------------
##
## Script name: Create safety zone layer ----
##
## Purpose of script: use wikidata to create a gpkg of safety zones
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

library(WikidataQueryServiceR)
library(dplyr)



# EXTRACT ----
# """""""""""""""""" ----


# Download the municipalities ----
# Define the SPARQL query

sparql_query <- "
SELECT DISTINCT ?municipality ?municipalityLabel ?NIS_INS ?NIS_EndDate ?emergencyZone ?emergencyZoneLabel WHERE {
  ?municipality wdt:P31 wd:Q493522;  # Instance of municipality in Belgium
               wdt:P17 wd:Q31.      # Country is Belgium
  OPTIONAL {
    ?municipality wdt:P361 ?emergencyZone.  # 'Part of' property
    ?emergencyZone wdt:P31 wd:Q3575878.     # Emergency zone
  }
  OPTIONAL {
    ?municipality wdt:P1567 ?NIS_INS.       # NIS code
    OPTIONAL { ?municipality p:P1567 [ ps:P1567 ?NIS_INS; pq:P582 ?NIS_EndDate ]. } # NIS end date
  }
  FILTER NOT EXISTS { ?municipality wdt:P576 ?dissolvedDate. } # Exclude dissolved municipalities
  SERVICE wikibase:label { bd:serviceParam wikibase:language \"nl\". }
}"

# Execute the query and fetch results
municipalities_wikidata <- query_wikidata(sparql_query, format = c("simple", "smart"))

# remove cases with an end date
municipalities_wikidata <- municipalities_wikidata %>% filter(is.na(NIS_EndDate))

# drop column NIS_EndDate
municipalities_wikidata <- municipalities_wikidata %>% select(-NIS_EndDate)

# QA: is the list still the same as what statbel says?
# Download list of municipalities from statbel ----

# Define the URL and local file path
url <- "https://statbel.fgov.be/sites/default/files/Over_Statbel_FR/Nomenclaturen/REFNIS_2025.xlsx"
local_file <- tempfile(fileext = ".xlsx")  # Temporary file for download

# Download the file
download.file(url, destfile = local_file, mode = "wb")

# Read the Excel file
municipalities_statbel <- readxl::read_xlsx(local_file, sheet = 1)

municipalities_statbel <- municipalities_statbel %>%
  filter(!is.na(Taal)) %>%
  select(NIS_INS='Code INS', name_statbel='Administratieve eenheden') %>%
  mutate(NIS_INS = as.numeric(NIS_INS))





# Join the datasets wikidata
muni_joined <- full_join(municipalities_statbel, municipalities_wikidata, by = "NIS_INS")

# test for obvious issues
if(nrow(muni_joined) == nrow(municipalities_statbel) & nrow(muni_joined) == nrow(municipalities_wikidata)){
  print("Municipality list still the same between wikidata & statbel")
} else {
  stop("Municipality list not the same anymore on wikidata & statbel")
}


# Load a geometry for the zones ----

## Download municipality official data
# portal: https://financien.belgium.be/nl/experten-partners/open-patrimoniumdata/datasets/downloadportaal

# download zip
# set the source
# open the shapefile 
municipal_geometry <- st_read(paste0(temporary_folder,"/municipalities_cleaned.gpkg"))
#plot(municipal_geometry$geometry)

municipal_geometry <- municipal_geometry %>% 
#  rename_all(tolower) %>%
  rename(geometry = geom)

# set NIS_INS to numeric
#municipal_geometry$NIS_INS <- as.numeric(municipal_geometry$NIS_INS)




# TRANSFROM ----
# """""""""""""""""" ----


# Join to wikidata ----
municipalities_w_geom <- full_join(municipal_geometry, municipalities_wikidata, by = "NIS_INS")

# check the count
if(nrow(municipalities_w_geom) == nrow(municipalities_wikidata)){
  print("Municipality geometry list still the same as wikidata")
} else {
  stop("Municipality geometry list not the same as wikidata anymore")
}

municipalities_aggregated <- municipalities_w_geom %>%
  group_by(emergencyZone) %>%
  summarize(geometry = st_union(geometry), .groups = "drop")
plot(municipalities_aggregated$geometry)



# LOAD ----
# """""""""""""""""" ----

# save as gpkg
st_write(municipalities_aggregated, paste0(temporary_folder,"/wikidata_security_zones.gpkg"), append=FALSE)

# TODO: compare to official data of the security zones
# zone geometry: https://opendata.fin.belgium.be/download/datasets/69bf46b0-e89f-11ec-a74a-9453308970f2_20250113_shp_31370_01000.zip
