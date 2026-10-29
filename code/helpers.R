
# File Title: Helpers
# File Purpose: Load packages, crosswalks, and helper functions for purple metros analysis
# File Author: Thomas Cronin

## Setup ----

#load packages
packages <- c("tidyverse", "janitor", "openxlsx", "httr2", "scales")
installed <- packages %in% rownames(installed.packages())
if (any(!installed)) {
  install.packages(packages[!installed])
}
invisible(lapply(packages, library, character.only = TRUE))

#shortcuts
end_date <- as.Date("2026-09-01")
start_date <- end_date - years(2)

#BLS credentials
bls_api_key <- Sys.getenv("BLS_API_KEY") #stored in ~/.Renviron
bls_user_agent <- "[INSERT EMAIL]" #BLS blocks bulk file downloads without a contact email

## Crosswalks ----

#county x CBSA crosswalk (July 2023 OMB delineations, uses CT planning regions)
county_cbsa_xwalk <- read.xlsx("data/raw/CBSA to FIPS Xwalk.xlsx") |>
  clean_names() |>
  filter(!is.na(fips_county_code)) |> #drop source notes at bottom of file
  mutate(cbsa_code = str_pad(as.character(cbsa_code), 5, side = "left", pad = "0"),
         fips = str_c(str_pad(fips_state_code, 2, side = "left", pad = "0"),
                      str_pad(fips_county_code, 3, side = "left", pad = "0"))) |>
  select(fips, cbsa_code, cbsa_title, cbsa_type = metropolitan_micropolitan_statistical_area)

#metro CBSA codes
metro_cbsa_codes <- county_cbsa_xwalk |>
  filter(cbsa_type == "Metropolitan Statistical Area") |>
  distinct(cbsa_code) |>
  pull(cbsa_code)

#short metro names, e.g. "Las Vegas, NV"
cbsa_names <- county_cbsa_xwalk |>
  distinct(cbsa_code, cbsa_title) |>
  mutate(metro = str_remove(cbsa_title, "-[^,]*(?=,)")) |> #keep first principal city only
  select(cbsa_code, metro)

#CES industries (sector = NA for supersector totals)
ces_industries <- tribble(
  ~industry_code, ~supersector,                            ~sector,
  "00000000",     "Total Nonfarm",                         NA,
  "15000000",     "Mining, Logging, and Construction",     NA,
  "10000000",     "Mining, Logging, and Construction",     "Mining and Logging",
  "20000000",     "Mining, Logging, and Construction",     "Construction",
  "30000000",     "Manufacturing",                         NA,
  "31000000",     "Manufacturing",                         "Durable Goods",
  "32000000",     "Manufacturing",                         "Nondurable Goods",
  "40000000",     "Trade, Transportation, and Utilities",  NA,
  "42000000",     "Trade, Transportation, and Utilities",  "Retail Trade",
  "43000000",     "Trade, Transportation, and Utilities",  "Transportation and Warehousing",
  "50000000",     "Information",                           NA,
  "55000000",     "Financial Activities",                  NA,
  "55520000",     "Financial Activities",                  "Finance and Insurance",
  "55530000",     "Financial Activities",                  "Real Estate and Rental and Leasing",
  "60000000",     "Professional and Business Services",    NA,
  "60540000",     "Professional and Business Services",    "Professional, Scientific, and Technical Services",
  "60550000",     "Professional and Business Services",    "Management of Companies and Enterprises",
  "60560000",     "Professional and Business Services",    "Administrative and Waste Services",
  "65000000",     "Private Education and Health Services", NA,
  "65610000",     "Private Education and Health Services", "Educational Services",
  "65620000",     "Private Education and Health Services", "Health Care and Social Assistance",
  "70000000",     "Leisure and Hospitality",               NA,
  "70710000",     "Leisure and Hospitality",               "Arts, Entertainment, and Recreation",
  "70720000",     "Leisure and Hospitality",               "Accommodation and Food Services",
  "80000000",     "Other Services",                        NA,
  "90000000",     "Government",                            NA,
  "90910000",     "Government",                            "Federal Government",
  "90920000",     "Government",                            "State Government",
  "90930000",     "Government",                            "Local Government")

#metro x SAE series crosswalk
sm_series_raw <- request("https://download.bls.gov/pub/time.series/sm/sm.series") |> #full BLS SAE series list
  req_user_agent(bls_user_agent) |>
  req_perform() |>
  resp_body_string() |>
  I() |> 
  read_tsv(col_types = cols(.default = "c"), trim_ws = TRUE) |>
  clean_names() |>
  mutate(across(everything(), str_trim))

metro_series_xwalk <- sm_series_raw |>
  filter(data_type_code == "01", #all employees, thousands
         area_code %in% metro_cbsa_codes,
         (seasonal == "S" & industry_code == "00000000") | #SA total nonfarm for headline series
           (seasonal == "U" & industry_code %in% ces_industries$industry_code)) |> #NSA industry detail
  filter(state_code == min(state_code), .by = area_code) |> #interstate metros are listed under each state; keep one copy
  distinct(series_id, cbsa_code = area_code, industry_code, seasonal)

## Visualization Functions ----

#standard graph formatting
format_graph <- function() {
  theme_minimal(base_family = "Times New Roman") +
    theme(plot.title = element_text(hjust = 0.5, face = "bold"),
          plot.caption = element_text(hjust = 0),
          panel.grid.major.x = element_blank(),
          panel.grid.minor = element_blank(),
          plot.background = element_rect(fill = "white", color = NA))
}

#one jobs-change barplot per political type; measure = "change" or "pct"
jobs_barplot <- function(data, var, measure = "change") {
  y_var <- if (measure == "pct") "pct_change" else "change"
  y_title <- if (measure == "pct") "Employment Change (%)" else "Employment Change"
  y_labels <- if (measure == "pct") label_percent(scale = 1) else label_comma()
  
  levels(data$political_type) |>
    set_names() |>
    map(\(type) {
      data |>
        filter(political_type == type) |>
        mutate(bar_color = if_else(.data[[var]] == "Total Nonfarm", "gold", "#19644D")) |>
        ggplot(aes(x = .data[[var]], y = .data[[y_var]], fill = bar_color)) +
        geom_col() +
        geom_hline(yintercept = 0) +
        scale_fill_identity() +
        scale_x_discrete(labels = label_wrap(30)) +
        scale_y_continuous(labels = y_labels) +
        labs(title = type, x = NULL, y = y_title) +
        format_graph() +
        theme(axis.text.x = element_text(angle = 45, hjust = 1))
    })
}

## Export Functions ----

#export to Excel with formatting
export_clean <- function(data, labels, filepath) {
  stopifnot(length(data) == length(labels))
  
  workbook <- createWorkbook()
  var_style <- createStyle(fontName = "Times New Roman", fontSize = 12,
                           textDecoration = "bold", halign = "center", valign = "center", wrapText = TRUE)
  data_style <- createStyle(fontName = "Times New Roman", fontSize = 12, valign = "center", wrapText = TRUE)
  
  walk2(data, labels, function(datasets, label) {
    addWorksheet(workbook, label)
    writeData(workbook, sheet = label, x = datasets)
    addStyle(workbook, label, style = var_style,
             rows = 1, cols = 1:ncol(datasets), gridExpand = TRUE)
    addStyle(workbook, label, style = data_style,
             rows = 2:(nrow(datasets) + 1), cols = 1:ncol(datasets), gridExpand = TRUE)
  })
  
  saveWorkbook(workbook, filepath, overwrite = TRUE)
}