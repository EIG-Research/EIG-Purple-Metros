
# File Title: 3 - Visualize Data
# File Purpose: Create figures for purple metros analysis
# File Author: Thomas Cronin
# Last Modified: 10/28/2026

## Setup ----

#load data
source("code/helpers.R")
political_shift_share <- readRDS("data/processed/Shift Share.rds")
political_sector_growth_nsa <- readRDS("data/processed/Political Sector Growth.rds")
political_supersector_growth_nsa <- readRDS("data/processed/Political Supersector Growth.rds")

## Shift Share Bar Plot ----

#create barplot
a <- ggplot(political_shift_share, aes(x = political_type, y = emp_change, fill = type)) +
  geom_col(position = "dodge") +
  labs(title = "Expected vs. Actual Job Growth Based on Industry Composition",
       x = NULL,
       y = "Employment Growth (pp.)",
       caption = str_c("Source: original calculations by author using Election Atlas and BLS SAE industry data.\n",
                       "All job changes are calculated from September 2024 to September 2026, the latest month of data currently available.")) +
  scale_fill_manual(name = "Type",
                    values = c("actual" = "gold", "predicted" = "forestgreen"),
                    labels = c("actual" = "Actual", "predicted" = "Predicted")) +
  format_graph()
a

#save
ggsave(plot = a, filename = "output/figures/Shift Share.png", width = 8, height = 5)

## Sector Changes by Political Type Bar Plots ----

#set order
supersector_bars_data <- political_supersector_growth_nsa |>
  arrange(supersector) |> 
  mutate(supersector = fct_inorder(supersector))

sector_bars_data <- political_sector_growth_nsa |>
  arrange(sector) |> 
  mutate(sector = fct_inorder(sector))

#create barplots
sector_bars_num <- jobs_barplot(sector_bars_data, "sector", measure = "change")
sector_bars_pct <- jobs_barplot(sector_bars_data, "sector", measure = "pct")
supersector_bars_num <- jobs_barplot(supersector_bars_data, "supersector", measure = "change")
supersector_bars_pct <- jobs_barplot(supersector_bars_data, "supersector", measure = "pct")

#save sector plots
dir.create("output/figures/sector barplots", showWarnings = FALSE)
walk2(sector_bars_num, names(sector_bars_num),
      \(plot, type) ggsave(paste0("output/figures/sector barplots/Supersector Employment Change - ", type, ".png"),
                           plot, width = 18, height = 8, dpi = 300, bg = "white"))
walk2(sector_bars_pct, names(sector_bars_num),
      \(plot, type) ggsave(paste0("output/figures/sector barplots/Supersector Pct Employment Change - ", type, ".png"),
                           plot, width = 18, height = 8, dpi = 300, bg = "white"))

#save supersector plots
dir.create("output/figures/supersector barplots", showWarnings = FALSE)
walk2(supersector_bars_num, names(supersector_bars_num),
      \(plot, type) ggsave(paste0("output/figures/supersector barplots/Supersector Employment Change - ", type, ".png"),
                           plot, width = 8, height = 6, dpi = 300, bg = "white"))
walk2(supersector_bars_pct, names(supersector_bars_num),
      \(plot, type) ggsave(paste0("output/figures/supersector barplots/Supersector Pct Employment Change - ", type, ".png"),
                           plot, width = 8, height = 6, dpi = 300, bg = "white"))
