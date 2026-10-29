
# File Title: 2 - Analysis
# File Purpose: Analyze employment data for purple metros analysis
# File Author: Thomas Cronin
# Last Modified: 10/28/2026

## Setup ----

#load packages and functions
source("code/helpers.R")

#import data
cbsa_political_colors <- readRDS("data/processed/CBSA Political Colors.rds")
metro_employment_sae <- readRDS("data/processed/Metro Employment by Month.rds")
metro_sector_nsa <- readRDS("data/processed/Metro Sector Employment by Month.rds")
metro_supersector_nsa <- readRDS("data/processed/Metro Supersector Employment by Month.rds")
population_clean <- readRDS("data/processed/Metro Population, 2025.rds")

## Analysis ----

### Summary Figures ----

#full metro jobs time series
metro_employment_seasonal <- metro_employment_sae |> 
  filter(seasonal == "S") |>
  left_join(select(cbsa_political_colors, cbsa_code, cbsa_name, political_type), by = "cbsa_code") |> 
  left_join(population_clean, by = "cbsa_code") |> 
  filter(!is.na(political_type))

#sector change by political type, Sep. 2024 vs. Sep. 2026
political_sector_growth_nsa <- metro_sector_nsa |>
  left_join(select(cbsa_political_colors, cbsa_code, political_type), by = "cbsa_code") |>
  filter(!is.na(political_type), date %in% c(start_date, end_date)) |>
  summarize(emp = sum(emp), .by = c(political_type, supersector, sector, date)) |>
  mutate(date = if_else(date == min(date), "start", "end")) |>
  pivot_wider(names_from = date, values_from = emp) |> 
  mutate(change = end - start,
         pct_change = change / start * 100,
         .by = political_type) |>
  select(political_type, supersector, sector, start, end, change, pct_change)
saveRDS(political_sector_growth_nsa, "data/processed/Political Sector Growth.rds")

#supersector change by political type, Sep. 2024 vs. Sep. 2026
political_supersector_growth_nsa <- metro_supersector_nsa |>
  left_join(select(cbsa_political_colors, cbsa_code, political_type), by = "cbsa_code") |>
  filter(!is.na(political_type), date %in% c(start_date, end_date)) |>
  summarize(emp = sum(emp), .by = c(political_type, supersector, date)) |>
  mutate(date = if_else(date == min(date), "start", "end")) |>
  pivot_wider(names_from = date, values_from = emp) |> 
  mutate(change = end - start,
         pct_change = change / start * 100,
         .by = political_type) |>
  select(political_type, supersector, start, end, change, pct_change)
saveRDS(political_supersector_growth_nsa, "data/processed/Political Supersector Growth.rds")

#private supersector growth by political type, Sep. 2024 vs. Sep. 2026
political_private_employment_nsa <- political_supersector_growth_nsa |> 
  filter(supersector %in% c("Government", "Total Nonfarm")) |> 
  select(-pct_change) |> 
  pivot_wider(names_from = supersector, values_from = (start:change)) |> 
  mutate(start_private = `start_Total Nonfarm` - `start_Government`,
         end_private = `end_Total Nonfarm` - `end_Government`,
         change_private = `change_Total Nonfarm` - `change_Government`,
         pct_change_private = (end_private - start_private)/start_private) |> 
  select(political_type, contains("private"))

### Ad-Hoc Figures ----

#very blue job growth without healthcare & social assistance sector
political_sector_growth_nsa_blue <- political_sector_growth_nsa |> 
  filter(political_type == "Very Blue", !sector == "Health Care and Social Assistance") |> 
  summarize(total_change = sum(change)) |> 
  pull(total_change)

#metro manufacturing shares
metro_manufacturing <- metro_supersector_nsa |> 
  filter(date == start_date, supersector %in% c("Manufacturing", "Total Nonfarm")) |> 
  pivot_wider(names_from = supersector, values_from = emp) |> 
  left_join((cbsa_names), by = "cbsa_code") |> 
  mutate(manufacturing_share = Manufacturing / `Total Nonfarm`) |> #stop code here for individual metro manufacturing shares
  summarize(avg_manufacturing_share = mean(manufacturing_share, na.rm = TRUE)) |> 
  pull(avg_manufacturing_share)

#purple metros with strongest/weakest SA total nonfarm growth, Jan. 2025 - Sep. 2026
purple_growth <- metro_employment_seasonal |>
  filter(political_type == "Purple", date %in% c(as.Date("2025-01-01"), end_date)) |>
  arrange(date) |>
  summarize(pct_change = last(emp) / first(emp) - 1, .by = cbsa_code)

purple_growth_metros <- bind_rows(
  slice_max(purple_growth, pct_change, n = 10) |> mutate(growth_group = "Strongest"),
  slice_min(purple_growth, pct_change, n = 10) |> mutate(growth_group = "Weakest")) |>
  select(growth_group, cbsa_code)

#purple metro manufacturing share of total nonfarm employment, Sep. 2024
purple_manufacturing_share <- metro_supersector_nsa |>
  filter(cbsa_code %in% purple_growth_metros$cbsa_code,
         supersector %in% c("Manufacturing", "Total Nonfarm"),
         date == start_date) |>
  pivot_wider(names_from = supersector, values_from = emp) |>
  mutate(manufacturing_share = Manufacturing / `Total Nonfarm`) |> 
  select(cbsa_code, manufacturing_share)

purple_manufacturing_table <- purple_growth_metros |>
  left_join(purple_manufacturing_share, by = "cbsa_code") |>
  left_join(cbsa_names, by = "cbsa_code") |> 
  select(growth_group, metro, manufacturing_share)

strongest_weakest_manufacturing_share <- purple_manufacturing_table |> 
  group_by(growth_group) |> 
  summarize(manufacturing_share = mean(manufacturing_share, na.rm = TRUE), .groups = "drop")

#government employment shares
political_gov_growth_nsa <- political_sector_growth_nsa |> 
  filter(supersector == "Government") |> 
  mutate(gov_type = case_when(sector == "Federal Government" ~ "Federal",
                              TRUE ~ "Local + State")) |> 
  group_by(political_type, gov_type) |> 
  summarize(across(c(start, end, change), ~ sum(.x)), .groups = "drop")

political_gov_growth_nsa_total <- political_gov_growth_nsa |> 
  group_by(political_type) |> 
  summarize(across(c(start, end, change), ~ sum(.x)), .groups = "drop") |> 
  mutate(gov_type = "Overall") |> 
  bind_rows(political_gov_growth_nsa) |> 
  arrange(political_type, gov_type) |> 
  mutate(pct_change = ((end - start) / start))

### Shift Share ----

#shift share inputs
shift_share_inputs <- metro_sector_nsa |>
  left_join(select(cbsa_political_colors, cbsa_code, political_type), by = "cbsa_code") |>
  filter(!is.na(political_type),
         date %in% c(start_date, end_date)) |>
  mutate(date = if_else(date == min(date), "start", "end")) |>
  summarize(emp = sum(emp), .by = c(political_type, supersector, date)) |>
  pivot_wider(names_from = date, values_from = emp) |>
  mutate(overall_growth = sum(end) / sum(start) - 1) |> #all-metro growth
  mutate(industry_growth = sum(end) / sum(start) - 1, .by = supersector) #all-metro growth by supersector

#calculate industry shift share
political_shift_share <- shift_share_inputs |>
  summarize(actual = (sum(end) / sum(start) - 1) * 100,
            predicted = sum(start * industry_growth) / sum(start) * 100,
            overall = first(overall_growth) * 100,
            .by = political_type) |>
  mutate(mix_effect = predicted - overall,
         local_effect = actual - predicted) |>
  select(political_type:predicted) |>
  pivot_longer(c(actual, predicted), names_to = "type", values_to = "emp_change")
saveRDS(political_shift_share, "data/processed/Shift Share.rds")

#clean for datawrapper
political_shift_share_export <- political_shift_share |> 
  pivot_wider(names_from = type, values_from = emp_change) |> 
  rename(`Political Type` = political_type, Actual = actual, Predicted = predicted)
write.xlsx(political_shift_share_export, "data/processed/Political Shift Share.xlsx")

#check against political supersector composition and growth
shift_share_table <- shift_share_inputs |>
  mutate(share = start / sum(start), .by = political_type) |>
  mutate(all_metros_comp = sum(start), .by = supersector) |>
  mutate(all_metros_comp = all_metros_comp / sum(start)) |>
  rename(industry_pct_growth = industry_growth) |> 
  pivot_wider(id_cols = c(supersector, industry_pct_growth, all_metros_comp),
              names_from = political_type, values_from = share, names_sort = TRUE) |>
  arrange(desc(industry_pct_growth)) |>
  clean_names() |> 
  rename_with(\(x) str_c(x, "_comp"), very_red:very_blue)

## Finalize and Save Extracts ----

#clean for exporting
metro_employment_seasonal_export <- metro_employment_seasonal |> 
  select(Date = date, `CBSA Code` = cbsa_code, `CBSA Name` = cbsa_name, `Total Employment` = emp, `2025 Population` = pop, `Political Type` = political_type)

political_employment_export <- metro_employment_seasonal |> 
  group_by(date, political_type) |> 
  summarize(emp = sum(emp), .groups = "drop") |> 
  bind_rows(metro_employment_seasonal |> summarize(emp = sum(emp), political_type = "Overall", .by = date)) |> 
  pivot_wider(names_from = political_type, values_from = emp) |> 
  select(Date = date, `Very Blue`, `Lean Blue`, Purple, `Lean Red`, `Very Red`, Overall)

political_population_export <- metro_employment_seasonal |> 
  slice_head(n = 1, by = cbsa_code) |> 
  group_by(political_type) |> 
  summarize(pop = sum(pop))

political_sector_growth_nsa_export <- political_sector_growth_nsa |> 
  mutate(pct_change = pct_change / 100) |> 
  select(`Political Type` = political_type, Supersector = supersector, Sector = sector,
         `Sep 2024 Employment` = start, `Sep 2026 Employment` = end, Change = change,
         `Percent Change` = pct_change)

#export to excel
export_clean(data = list(metro_employment_seasonal_export, political_employment_export, political_population_export, political_sector_growth_nsa_export),
             labels = list("CBSA Employment", "Political Employment", "Political Population", "Political Sectors"),
             filepath = "output/Employment Data unformatted.xlsx")
