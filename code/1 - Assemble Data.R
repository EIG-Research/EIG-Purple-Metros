
# File Title: 1 - Assemble Data
# File Purpose: Import and clean election and jobs data for purple metros analysis
# File Author: Thomas Cronin
# Last Modified: 10/28/2026

## Setup ----

#load packages and functions
source("code/helpers.R")

#load election and population data
election_results <- read_csv("data/raw/2024 Presidential.csv") #2024 presidential election results, NOT included in replication package and available for purchase here: https://uselectionatlas.org/RESULTS/
population <- read_csv("data/raw/cbsa-est2025-alldata.csv", locale = locale(encoding = "latin1")) #2025 census CBSA population estimates (CBSA-EST2025-alldata), available here: https://www.census.gov/data/tables/time-series/demo/popest/2020s-total-metro-and-micro-statistical-areas.html
#political aggregations used for this analysis are included in the repository as "CBSA Political Colors.rds"

#pull SAE data, 50 requests at a time to avoid blocks
series_batches <- split(metro_series_xwalk$series_id,
                        ceiling(seq_along(metro_series_xwalk$series_id) / 50))
sae_batch_dir <- "data/raw/BLS SAE API Batches" #delete this folder to pull fresh data
dir.create(sae_batch_dir, showWarnings = FALSE)

walk(names(series_batches), \(batch_name) {
  batch_file <- file.path(sae_batch_dir, str_c("batch_", batch_name, ".rds"))
  if (file.exists(batch_file)) return() #skip batches already saved
  resp <- request("https://api.bls.gov/publicAPI/v2/timeseries/data/") |>
    req_body_json(list(seriesid = as.list(series_batches[[batch_name]]), startyear = "2023",
                       endyear = as.character(year(Sys.Date())),
                       registrationkey = bls_api_key)) |>
    req_retry(max_tries = 5) |> #retry 429/503 errors with increasing waits
    req_perform() |>
    resp_body_json()
  if (resp$status != "REQUEST_SUCCEEDED") stop("BLS request failed on batch ", batch_name, ": ", paste(unlist(resp$message), collapse = " "))
  write_rds(resp, batch_file)
}, .progress = TRUE)
stopifnot(length(list.files(sae_batch_dir)) == length(series_batches)) #confirm every batch saved

metro_employment_sae <- list.files(sae_batch_dir, full.names = TRUE) |>
  map(read_rds) |>
  map("Results") |>
  map("series") |>
  list_flatten() |>
  map_dfr(\(series) map_dfr(series$data, \(obs) tibble(
    series_id = series$seriesID,
    period = obs$period,
    year_int = as.integer(obs$year),
    emp = as.numeric(obs$value) * 1000
  ))) |>
  filter(period != "M13") |> #drop annual-average rows
  mutate(date = make_date(year_int, as.integer(str_remove(period, "M")), 1)) |>
  filter(date >= as.Date("2023-05-01")) |>
  left_join(metro_series_xwalk, by = "series_id") |>
  select(cbsa_code, industry_code, seasonal, date, emp) |>
  arrange(cbsa_code, industry_code, date)
saveRDS(metro_employment_sae, "data/processed/Metro Employment by Month.rds")

## Clean SAE Jobs Data ----

#NSA industry detail with supersector/sector labels
sector_detail_nsa <- metro_employment_sae |>
  filter(seasonal == "U") |>
  left_join(ces_industries, by = "industry_code")

supersectors_with_detail <- ces_industries |>
  filter(!is.na(sector)) |>
  distinct(supersector) |>
  pull(supersector)

#part of each supersector not covered by published sectors
sector_remainder <- sector_detail_nsa |>
  filter(supersector %in% supersectors_with_detail) |>
  filter(any(is.na(sector)), .by = c(cbsa_code, date, supersector)) |> #only where BLS publishes the supersector total
  summarize(emp = sum(emp[is.na(sector)]) - sum(emp[!is.na(sector)]),
            .by = c(cbsa_code, date, supersector)) |>
  filter(any(round(emp) != 0), .by = c(cbsa_code, supersector)) |> #drop remainders that are zero because published sectors cover the whole supersector
  mutate(sector = paste("Other", supersector))

#metro-level sector employment
metro_sector_nsa <- sector_detail_nsa |>
  filter(!is.na(sector) | !supersector %in% c("Total Nonfarm", supersectors_with_detail)) |>
  mutate(sector = coalesce(sector, supersector)) |>
  bind_rows(sector_remainder) |>
  select(cbsa_code, date, supersector, sector, emp)
saveRDS(metro_sector_nsa, "data/processed/Metro Sector Employment by Month.rds")

#metro-level supersector employment + Total Nonfarm
metro_supersector_nsa <- sector_detail_nsa |>
  filter(is.na(sector)) |>
  select(cbsa_code, date, supersector, emp)
saveRDS(metro_supersector_nsa, "data/processed/Metro Supersector Employment by Month.rds")

## Clean Election Data ----

#aggregate to CBSAs
cbsa_political_colors <- election_results |> 
  slice(-1) |> 
  clean_names() |> 
  select(-c(robert_f_kennedy_jr:x0_42)) |> 
  mutate(across(c(total_vote:donald_j_trump), as.numeric),
         fips = str_pad(fips, 5, side = "left", pad = "0"),
         state_fips = str_sub(fips, 1, 2)) |> 
  filter(state_fips != "02", #drop Alaska; didn't report 2024 election results by county
         !(state_fips == "09" & geographic_subtype == "County")) |> #use planning regions for Connecticut
  left_join(county_cbsa_xwalk, by = "fips") |>
  group_by(cbsa_code) |>
  summarize(across(c(total_vote:donald_j_trump), \(x) sum(x, na.rm = TRUE)), 
            state_fips = first(state_fips),
            cbsa_name = first(cbsa_title),
            .groups = "drop") |> 
  mutate(trump_share = (donald_j_trump / total_vote) * 100,
         harris_share = (kamala_d_harris / total_vote) * 100,
         diff = trump_share - harris_share,
         political_type = case_when(diff > 10 ~ "Very Red",
                                    diff <= 10 & diff > 3 ~ "Lean Red",
                                    diff <= 3 & diff >= -3 ~ "Purple",
                                    diff < -3 & diff >= -10 ~ "Lean Blue",
                                    diff < -10 ~ "Very Blue"),
         political_type = factor(political_type, levels = c("Very Blue", "Lean Blue", "Purple", "Lean Red", "Very Red"))) |> 
  select(cbsa_code, cbsa_name, political_type)
saveRDS(cbsa_political_colors, "data/processed/CBSA Political Colors.rds")

## Clean Population Estimates ----

#clean data
population_clean <- population |> 
  clean_names() |> 
  filter(lsad == "Metropolitan Statistical Area") |> 
  mutate(cbsa_code = as.character(cbsa)) |> 
  select(cbsa_code, pop = popestimate2025)
saveRDS(population_clean, "data/processed/Metro Population, 2025.rds")
