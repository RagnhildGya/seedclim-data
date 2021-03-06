#### build seedclim comm database

## Load packages ####
library("DBI")
library("RSQLite")
library("readxl")
library("tidyverse")
library("assertr")
library("conflicted")
conflict_prefer("filter", "dplyr")

#function to add data to database - padding for missing columns ####
db_pad_write_table <- function(conn, table, value, row.names = FALSE,
                            append = TRUE, ...) {
  #get extra columns from DB
  all_cols <- dbGetQuery(con, paste("select * from", table, "limit 0;"))
  value <- bind_rows(all_cols, value)

  #add to database
  dbWriteTable(con, table, value = value,
               row.names = row.names, append = append, ...)
}

## make database ####
if (file.exists("database/seedclim.sqlite")) {
  file.remove("database/seedclim.sqlite")
}
con <- dbConnect(SQLite(), dbname = "database/seedclim.sqlite")

##set up structure ####

setup <- readChar("databaseUtils/seedclimstructure.txt", nchar = 100000)
sapply(paste("CREATE", strsplit(setup, "CREATE")[[1]][-(1:2)]),
       dbExecute, conn = con)

dbListTables(con)

## optionally extract meta data from old mysql
extract_from_mysql <- FALSE
if (extract_from_mysql) {
  old_DB <- dbConnect(RMySQL::MySQL(), group = "seedclim")
}

### load taxa ####
if (extract_from_mysql) {
  oldDB_taxon <- dbGetQuery(old_DB, "select * from taxon")
  write_csv(oldDB_taxon, path = "databaseUtils/taxon_table.csv")
}

taxa <- read_csv("databaseUtils/taxon_table.csv", quote = "'") %>%
  mutate(species = recode(
    species,
  #old code = new code
    "Vis alp" = "Vis.alp",
    "Gent.sp" = "Gen.sp",
    "Ort sec" = "Ort.sec"
  )) %>%
  bind_rows(read_csv(
"species,speciesName,family,functionalGroup,lifeSpan
Gale.sp,Galeopsis sp,Lamiaceae,forb,perennial
Cer,Cerastium sp??,Caryophyllaceae,forb,perennial
Ran...,Ranunculus sp,Ranunculaceae,forb,perennial
X...,???,???,NA,NA
Dia.lan,Dianthus lanceolata!?!,Caryophyllaceae?,forb,perennial
Hol.lan,Not Holcus??,Poaceae,graminoid,perennial
Dia.med,Dianthus not media??,??,forb,perennial
X....1,???,???,NA,NA
Car.sp1,Carex sp1??,Cyperaceae,graminoid,perennial
Åkerplante,Crop plant???,Cropfamily,forb,perennial

Agr.can,Agrostis canina?,Poaceae,graminoid,perennial
Cre.pal,Crepis paludosa?,Asteraceae,forb,perennial
Frag.vir,Fragaria viridis,Rosaceae,forb,perennial
Hie.ore,Hieracium oreadea?,Asteraceae,forb,perennial
Sch.gig,Schedonorus giganteus,Poaceae,graminoid,perennial
Ste.bor,Stellaria borealis,Caryophyllaceae,forb,perennial
Pop.tre,Populus tremula,Salicaceae,woody,perennial
Ped.pal,Pedicularis palustris,Orobanchaceae,forb,perennial
Are.ser,Arenaria serpyllifolia,Carophyllaceae,forb,annual
Sch.pra,Schedonorus pratensis,Poaceae,graminoid,perennial
Luz.syl,Luzula sylvatica,Juncaceae,graminoid,perennial
Sal.lan,Salix lanata,Salicaceae,woody,perennial
Ver.ver,Veronica verna,Plantaginaceae,forb,annual 
"))
  


db_pad_write_table(conn = con, table = "taxon",
                value = taxa %>% select(species, speciesName, family, comment))

## load traits
if (extract_from_mysql) {
  oldDB_traits <- dbGetQuery(old_DB, "select * from moreTraits")
  write_delim(oldDB_traits, path = "databaseUtils/moreTraits_table.tab",
              delim = "\t")
}

traits <- read_delim("databaseUtils/moreTraits_table.tab", quote = "'",
                     delim = "\t")

all_traits <- traits %>%
  rename(Norwegian_name = `Norwegian name`) %>%
  full_join(select(taxa, -speciesName, -family, -comment)) %>%
  group_by(species)

all_traits %>%
  select_if(is.numeric) %>%
  gather(key = trait, value = value, -species) %>%
  filter(!is.na(value)) %>%
  db_pad_write_table(conn = con, table = "numeric_traits", value = .)

all_traits %>%
  select_if(is.character) %>%
  gather(key = trait, value = value, -species) %>%
  filter(!is.na(value)) %>%
  db_pad_write_table(conn = con, table = "character_traits", value = .)


## load sites ####
if (extract_from_mysql) {
  oldDB_sites <- dbGetQuery(old_DB, "select * from sites")
  write_csv(oldDB_sites, path = "databaseUtils/site_table.csv")
}

sites <- read_csv("databaseUtils/site_table.csv") %>%
  rename(annualPrecipitation_gridded = Annualprecipitation_gridded,
         temperature_level = Temperature_level,
         summerTemperature_gridded =  SummerTemperature_gridded,
         precipitation_level = Precipitation_level)

site_fields <- dbListFields(conn = con, "sites")


db_pad_write_table(conn = con, table = "sites",
                value = sites %>% select(one_of(site_fields)))

## site attributes
sites %>%
  group_by(siteID) %>% #will force addition of siteID column
  select(-one_of(site_fields)) %>%
  gather(key = variable, value = value, -siteID) %>%
  db_pad_write_table(conn = con, table = "site_attributes", value = .)

  


## load blocks ####
if (extract_from_mysql) {
  oldDB_blocks <- dbGetQuery(old_DB, "select * from blocks")
  write_csv(oldDB_blocks, path = "databaseUtils/blocks_table.csv")
}

blocks <- read_csv("databaseUtils/blocks_table.csv")
db_pad_write_table(conn = con, table = "blocks", value = blocks)


## load plots ####
if (extract_from_mysql) {
  oldDB_plots <- dbGetQuery(old_DB, "select * from plots")
  write_csv(oldDB_plots, path = "databaseUtils/plots_table.csv")
}

plots <- read_csv("databaseUtils/plots_table.csv")

db_pad_write_table(conn = con, table = "plots", value = plots)

## load turfs ####
if (extract_from_mysql) {
  oldDB_turfs <- dbGetQuery(old_DB, "select * from turfs")
  write_csv(oldDB_turfs, path = "databaseUtils/turfs_table.csv")
}

turfs <- read_csv("databaseUtils/turfs_table.csv")

db_pad_write_table(conn = con, table = "turfs", value = turfs)



## load mergeDictionary ####
if (extract_from_mysql) {
  oldDB_mergedictionary <- dbGetQuery(old_DB, "select * from mergedictionary")
  write_csv(oldDB_mergedictionary, path = "databaseUtils/mergedictionary.csv")
  dbDisconnect(old_DB)
}

merge_dictionary <- read_csv("databaseUtils/mergedictionary.csv") %>%
  mutate(newID = recode(newID, "Vis alp" = "Vis.alp")) %>%
  bind_rows(
    read_csv(comment = "#",
"oldID,newID
Salix.graa,Sal.sp
Vis.alp,Vis.alp
Gen.sp.,Gen.sp
Car.Cap,Car.cap
Galeopsis.sp,Gale.sp
Seedlings,NID.seedling
Sax.aiz.,Sax.aiz
Dry.sp,Gym.dry
Tof.cal,Tof.pus
#2019 additions
Cir.vul,Cir.pal
Cirsium.sp,Cir.pal
Solidago,Sol.vir
Pin.sax,Pim.sax
Pinguicula.sp.,Pin.vul
Car.var,Car.vag
Dac.alp,Dac.glo
Gal.sp,Gal.uli
"))



## load main data ####
source("inst/uploadDataSource/importcommunityNY_test_16.des.2013.r")

## get list of data files
datafiles <- dir(path = "rawdata/", pattern = "csv$",
                 full.names = TRUE, recursive = TRUE)

#exclude 2019 raw files (keep processed)
datafiles <- str_subset(datafiles, pattern = "2019_data", negate = TRUE)

#check taxonomy
meta_cols <- c("DestinationSite", "DestinationBlock", "originPlotID", "TTtreat",
           "destinationPlotID", "turfID", "RTtreat", "GRtreat", "subPlot",
           "year",  "date",  "Measure", "recorder", "pleuro", "acro",  "liver",
           "lichen", "litter", "soil", "rock", "totalVascular",
           "totalBryophytes", "totalLichen", "vegetationHeight", "mossHeight",
           "comment",  "X",  "X.1", "X.2", "missing")

## process 2019 data
source("databaseUtils/2019_temp.R")


datafiles %>% #grep("2017", ., value = TRUE) %>%
  set_names %>%
  map(function(x) {
  print(x)
  f <- read.table(x, header = TRUE, sep = ",", nrows = 2, comment = "")
  if (ncol(f) == 1) {
    f <- read.table(x, header = TRUE, sep = ";", nrows = 2, comment = "")
  }
  setdiff(names(f), c(meta_cols, merge_dictionary$oldID, taxa$species))
  })


datafiles %>% #grep("2017", ., value = TRUE) %>%
  map(import_data, con = con, merge_dictionary = merge_dictionary)


## do corrections

source("databaseUtils/speciesCorrections.R")
