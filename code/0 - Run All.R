# =============================================================================
# 0 - Run All.R
# Replicates the analysis for "The Country’s Most Contested Metro Battlegrounds Are Also the Fastest Growing" from start to finish.
# Run from the repository root (open EIG-Purple-Metros.Rproj first).
# =============================================================================

# ---- Settings ---------------------------------------------------------------
# Set a step to FALSE to skip it, e.g., to rerun the analysis and visuals
# without re-downloading the data. Skipped steps leave the files already in
# data/processed/ in place for later scripts to use.
run_import   <- TRUE
run_analysis <- TRUE
run_visuals  <- TRUE

# ---- Setup ------------------------------------------------------------------
# Stop early if the working directory isn't the repository root
if (!dir.exists("code")) {
  stop("Set the working directory to the repository root (open the .Rproj file).")
}

# Create any missing data and output folders
for (folder in c("data/raw", "data/processed", "output/figures")) {
  dir.create(folder, recursive = TRUE, showWarnings = FALSE)
}

# Runs one script in a fresh environment and reports how long it took
run_script <- function(script) {
  message("\n==== Running ", script, " ====")
  start <- Sys.time()
  source(file.path("code", script), local = new.env(parent = globalenv()))
  message("Finished ", script, " in ", format(round(Sys.time() - start, 1)))
}

# ---- Run --------------------------------------------------------------------
total_start <- Sys.time()

if (run_import)   run_script("1 - Assemble Data.R")
if (run_analysis) run_script("2 - Analysis.R")
if (run_visuals)  run_script("3 - Visualize Data.R")

message("\nAll scripts finished in ", format(round(Sys.time() - total_start, 1)))

# ---- Record the environment -------------------------------------------------
# R and package versions used for this run; copy these into the README
print(sessionInfo())
