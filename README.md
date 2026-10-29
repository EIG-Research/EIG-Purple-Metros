
# Purple Metros: Job Growth by 2024 Presidential Vote
Repository for the EIG analysis ["The Country's Most Contested Metro Battlegrounds Are Also the Fastest Growing"](https://agglomerations.eig.org/p/the-fastest-growing-metros-are-also) by Kenan Fikri and Thomas Cronin, published on October 29, 2026.

This descriptive analysis classifies U.S. metropolitan areas by their 2024 presidential vote margin and tracks how employment has changed in each group since President Trump took office in January 2025. Purple metros, where Trump and Harris finished within 3 percentage points of each other, have posted the strongest job growth since January 2025, while very blue metros still have fewer jobs than they did at inauguration. Differences in industry mix do not explain the gap.

## Repository map

| Path | Contents |
|---|---|
| `code/helpers.R` | Packages, BLS credentials, the county-to-CBSA and SAE series crosswalks, CES industry definitions, the strongest/weakest purple metro lists, and plotting and Excel export functions. Sourced by every other script. |
| `code/0 - Run All.R` | Replicates the entire project from start to finish. Each step can be turned off separately. |
| `code/1 - Assemble Data.R` | Downloads BLS metro employment data and cleans the election, population, and employment data. |
| `code/2 - Analysis.R` | The analysis. Aggregates employment by political group, calculates sector and supersector job changes, government and manufacturing breakdowns, and a shift-share decomposition, then exports the chart data. |
| `code/3 - Visualize Data.R` | The shift-share figure and sector/supersector job change bar plots for each political group. |
| `data/raw/` | Inputs as received. |
| `data/processed/` | Checkpoints written by scripts 1 and 2. |
| `output/` | `Employment Data.xlsx`, the data behind the Datawrapper charts in the piece. |
| `output/figures/` | The shift-share chart, plus job change bar plots by political group in `sector barplots/` and `supersector barplots/`. |

## Data sources

| Dataset Name | File | Provider | Contents | Universe |
|---|---|---|---|---|
| 2024 Presidential Election Results | Aggregations are saved as `data/processed/CBSA Political Colors.R`; raw data is only available for purchase from the owner. | [Dave Leip's Atlas of U.S. Presidential Elections](https://uselectionatlas.org/) | Votes cast for each presidential candidate, plus total votes | All U.S. counties (Connecticut planning regions), excluding Alaska; 2024 general election |
| State and Metro Area Employment (SAE) | Not saved; downloaded via API by `code/1 - Assemble Data.R` | [U.S. Bureau of Labor Statistics](https://www.bls.gov/sae/) | Monthly nonfarm employment, all employees (thousands) | All metropolitan statistical areas; May 2023 to the latest available month (September 2026 at publication). Seasonally adjusted total nonfarm, plus non-seasonally adjusted supersector and sector detail |
| SAE Series List | Not saved; downloaded by `code/helpers.R` | [U.S. Bureau of Labor Statistics](https://download.bls.gov/pub/time.series/sm/) | Series IDs mapped to area, industry, data type, and seasonal adjustment | All SAE series |
| Metropolitan and Micropolitan Population Estimates | `cbsa-est2025-alldata.csv` | [U.S. Census Bureau](https://www.census.gov/data/tables/time-series/demo/popest/2020s-total-metro-and-micro-statistical-areas.html) | Annual resident population estimates (CBSA-EST2025-alldata) | All metropolitan statistical areas; July 1, 2025 (Vintage 2025) |
| Core Based Statistical Area Delineations | `CBSA to FIPS Xwalk.xlsx` | [U.S. Census Bureau](https://www.census.gov/geographies/reference-files/time-series/demo/metro-micro/delineation-files.html), from OMB delineations | County-to-CBSA crosswalk with CBSA titles and metro/micro status | All U.S. counties and county equivalents in a CBSA; July 2023 OMB delineations (Connecticut planning regions) |

## How the build works

1. **Build crosswalks.** `helpers.R` reads the July 2023 OMB delineation file and builds a county FIPS-to-CBSA crosswalk, a list of metropolitan CBSA codes, and short metro names (first principal city and state, e.g., "Las Vegas, NV"). It then downloads the full SAE series list and keeps "all employees" series for every metro: seasonally adjusted total nonfarm, plus non-seasonally adjusted series for each supersector and sector listed in `ces_industries`. Metros that cross state lines appear once per state in the SAE files, so only one copy of each is kept.
2. **Download employment data.** Script 1 queries the BLS API v2 in batches of 50 series, drops annual averages, converts values from thousands to jobs, and keeps May 2023 onward. This window lets growth over the 19 months after January 2025 be compared with growth over the 19 months before it.
3. **Clean sector detail.** Non-seasonally adjusted series are labeled by supersector and sector. Where BLS publishes a supersector total but its published sectors don't add up to it, the difference is kept as an "Other [Supersector]" sector so that sectors sum to supersector totals. Remainders that are zero in every month are dropped. Supersectors with no sector detail (e.g., Information, Other Services) are treated as their own sector.
4. **Classify metros politically.** County-level 2024 results are aggregated to CBSAs. Alaska is dropped because it does not report presidential results by county, and Connecticut is measured by planning region to match the 2023 delineations. Each CBSA's margin is Trump's share of total votes cast minus Harris's share:
   - **Very Red:** Trump margin greater than 10 points
   - **Lean Red:** Trump margin greater than 3 and up to 10 points
   - **Purple:** margin within ±3 points
   - **Lean Blue:** Harris margin greater than 3 and up to 10 points
   - **Very Blue:** Harris margin greater than 10 points
5. **Headline employment trends.** Script 2 joins seasonally adjusted total nonfarm employment to each metro's political group and 2025 population, then sums employment by group and month. In the piece, these totals are indexed to January 2025, compared over the 19 months before and after inauguration, and used to count the share of metros in each group with positive growth since January 2025. [CONFIRM: the indexing, pre/post growth rates, share of metros growing, and the strongest/weakest purple metro rankings hard-coded in `helpers.R` were calculated outside R from `Employment Data.xlsx`.]
6. **Industry changes.** Because SAE does not publish seasonally adjusted data at the metro-sector level, industry results use non-seasonally adjusted employment and compare September 2024 with September 2026 to control for seasonality. Script 2 calculates job changes by political group for each sector and supersector, and also calculates:
   - Private sector employment (total nonfarm minus government)
   - Federal versus state and local government job changes
   - Very blue job growth excluding health care and social assistance
   - Manufacturing's share of total nonfarm employment (September 2024): the unweighted average across all metros and the averages for the 10 fastest- and 10 slowest-growing purple metros
7. **Shift share.** For each political group, predicted growth applies each supersector's all-metro growth rate to the group's starting supersector employment. This is compared with the group's actual growth. A gap between the two shows how much of a group's performance comes from local conditions rather than industry mix. `shift_share_table` reports each group's supersector composition next to all-metro composition and supersector growth as a check.

Total nonfarm trends use seasonally adjusted data, while industry results use non-seasonally adjusted data over a year-over-year window, so the two sets of figures are not directly comparable. SAE estimates are revised each month and benchmarked every March, and the most recent month is preliminary, so rerunning script 1 will pull revised and newer data. All geography follows the July 2023 OMB delineations. The jobs analysis covers metropolitan areas only; micropolitan areas appear in the election classification but not the employment data. BLS does not publish every sector in every metro, so sector-level totals cover fewer metros than supersector totals.

## Outputs

| File | Created by | Contents |
|---|---|---|
| `data/processed/Metro Employment by Month.rds` | Script 1 | Raw SAE pull: monthly employment by metro, industry code, and seasonal adjustment status |
| `data/processed/Metro Sector Employment by Month.rds` | Script 1 | Non-seasonally adjusted monthly employment by metro and sector, including "Other" remainders |
| `data/processed/Metro Supersector Employment by Month.rds` | Script 1 | Non-seasonally adjusted monthly employment by metro and supersector, including total nonfarm |
| `data/processed/CBSA Political Colors.rds` | Script 1 | Political classification for each CBSA based on the 2024 presidential vote margin |
| `data/processed/Metro Population, 2025.rds` | Script 1 | 2025 population estimate for each metro |
| `data/processed/Political Sector Growth.rds` | Script 2 | Employment change by political group and sector, September 2024 to September 2026 |
| `data/processed/Political Supersector Growth.rds` | Script 2 | Employment change by political group and supersector, September 2024 to September 2026 |
| `data/processed/Shift Share.rds` | Script 2 | Actual and industry-mix-predicted employment growth by political group |
| `data/processed/Political Shift Share.xlsx` | Script 2 | Chart data for the shift-share figure |
| `output/Employment Data.xlsx` | Script 2 | Chart data for the employment index, growth comparison, share of metros growing, metro maps, and population figures. Sheets: metro-level monthly employment with population and political group; monthly employment by political group; 2025 population by political group; sector employment change by political group |

## Reproducing the analysis

Built and run under R [VERSION] with `tidyverse`, `janitor`, `openxlsx`, `httr2`, and `scales`. `helpers.R` installs any that are missing.

1. Place `2024 Presidential.csv`, `cbsa-est2025-alldata.csv`, and `CBSA to FIPS Xwalk.xlsx` in `data/raw/`. (Note: if you do not have access to the Election Atlas data, you should still be able to reproduce the results of the analysis from `2 - Analysis.R` onwards using the saved data extracts.)
2. Save a [BLS API v2 key](https://data.bls.gov/registrationEngine/) as `BLS_API_KEY` in `.Renviron`, and replace `[INSERT EMAIL]` in `code/helpers.R` with a contact email. BLS blocks bulk file downloads without one.
3. Open `EIG-Purple-Metros.Rproj`, or otherwise set the working directory to the repository root. All paths are relative.
4. Run `code/0 - Run All.R` or the following scripts in order:

```bash
Rscript "code/1 - Assemble Data.R"
Rscript "code/2 - Analysis.R"
Rscript "code/3 - Visualize Data.R"
```

Script 1 pulls the latest SAE data, including any revisions. To reproduce the published figures exactly, set `run_import <- FALSE` in `0 - Run All.R` to use the checkpoints saved in `data/processed/`, or set a manual exclusion to drop any jobs data after September 2026.

## Contact

For questions about the code or data, you may reach out to Thomas Cronin (thomas@eig.org), Kenan Fikri (kenan@eig.org), or research@eig.org.
