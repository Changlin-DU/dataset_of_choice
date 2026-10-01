# 01_download_data.R
#
# Project:
# Priced Out: How Did Housing Affordability Change
# Across U.S. States from 2019 to 2024?
#
# Purpose:
# 1. Download state-level income and home-value data from
#    the 2019 and 2024 ACS 1-year estimates.
# 2. Download the 30-year fixed mortgage rate from FRED.
# 3. Save all downloaded data in data/raw/.
#
# API keys must be stored in ~/.Renviron as:
# FRED_API_KEY=your_key
# CENSUS_API_KEY=your_key
#
# Never write API keys directly in this script.


# 1. Check required packages ----------------------------------------------

required_packages <- c(
  "dplyr",
  "purrr",
  "readr",
  "jsonlite",
  "fredr"
)

missing_packages <- required_packages[
  !vapply(
    required_packages,
    requireNamespace,
    logical(1),
    quietly = TRUE
  )
]

if (length(missing_packages) > 0) {
  stop(
    "Install the following packages before continuing: ",
    paste(missing_packages, collapse = ", ")
  )
}


# 2. Load packages --------------------------------------------------------

library(dplyr)
library(purrr)
library(readr)
library(jsonlite)
library(fredr)


# 3. Check API keys -------------------------------------------------------

fred_api_key <- Sys.getenv("FRED_API_KEY")
census_api_key <- Sys.getenv("CENSUS_API_KEY")

if (fred_api_key == "") {
  stop(
    "FRED_API_KEY was not found. ",
    "Add it to ~/.Renviron and restart RStudio."
  )
}

if (census_api_key == "") {
  stop(
    "CENSUS_API_KEY was not found. ",
    "Add it to ~/.Renviron and restart RStudio."
  )
}

message("Both API keys were found successfully.")


# 4. Confirm project folders exist ----------------------------------------

required_directories <- c(
  "data/raw",
  "data/processed",
  "output/figures"
)

walk(
  required_directories,
  ~ dir.create(
    .x,
    recursive = TRUE,
    showWarnings = FALSE
  )
)


# 5. Define the ACS download function -------------------------------------

download_acs_state <- function(year) {
  
  # ACS variables:
  #
  # B19013_001E:
  # Median household income estimate
  #
  # B19013_001M:
  # Margin of error for median household income
  #
  # B25077_001E:
  # Median value of owner-occupied housing units
  #
  # B25077_001M:
  # Margin of error for median home value
  
  acs_variables <- paste(
    "NAME",
    "B19013_001E",
    "B19013_001M",
    "B25077_001E",
    "B25077_001M",
    sep = ","
  )
  
  census_url <- paste0(
    "https://api.census.gov/data/",
    year,
    "/acs/acs1",
    "?get=",
    utils::URLencode(
      acs_variables,
      reserved = TRUE
    ),
    "&for=state%3A%2A",
    "&key=",
    utils::URLencode(
      census_api_key,
      reserved = TRUE
    )
  )
  
  message("Downloading ", year, " ACS data...")
  
  census_response <- tryCatch(
    {
      jsonlite::fromJSON(census_url)
    },
    error = function(error_condition) {
      stop(
        "The Census API request failed for ",
        year,
        ". The server did not return valid JSON. ",
        "Check that the Census API key is activated and try again. ",
        "Original error: ",
        conditionMessage(error_condition),
        call. = FALSE
      )
    }
  )
  
  if (
    !is.matrix(census_response) &&
    !is.data.frame(census_response)
  ) {
    stop(
      "The Census API returned an unexpected result for ",
      year,
      ".",
      call. = FALSE
    )
  }
  
  census_data <- as.data.frame(
    census_response[-1, , drop = FALSE],
    stringsAsFactors = FALSE
  )
  
  names(census_data) <- census_response[1, ]
  
  census_data |>
    transmute(
      year = as.integer(year),
      
      # Preserve leading zeros in state FIPS codes.
      state_fips = as.character(state),
      
      state_name = as.character(NAME),
      
      median_household_income =
        readr::parse_double(B19013_001E),
      
      income_moe =
        readr::parse_double(B19013_001M),
      
      median_home_value =
        readr::parse_double(B25077_001E),
      
      home_value_moe =
        readr::parse_double(B25077_001M)
    )
}


# 6. Download 2019 and 2024 ACS data --------------------------------------

acs_years <- c(2019, 2024)

acs_raw <- purrr::map_dfr(
  acs_years,
  download_acs_state
)


# 7. Validate ACS data ----------------------------------------------------

if (nrow(acs_raw) == 0) {
  stop("The ACS download returned no observations.")
}

if (!all(acs_years %in% acs_raw$year)) {
  stop("One or more requested ACS years are missing.")
}

if (anyDuplicated(acs_raw[c("year", "state_fips")]) > 0) {
  stop("The ACS data contain duplicate year-state observations.")
}

acs_missing_summary <- acs_raw |>
  summarise(
    missing_income =
      sum(is.na(median_household_income)),
    
    missing_home_value =
      sum(is.na(median_home_value))
  )

if (
  acs_missing_summary$missing_income > 0 ||
  acs_missing_summary$missing_home_value > 0
) {
  warning(
    "The ACS data contain missing income or home-value observations."
  )
}


# 8. Save raw ACS data ----------------------------------------------------

acs_output_path <- paste0(
  "data/raw/",
  "acs_state_housing_income_2019_2024.csv"
)

write_csv(
  acs_raw,
  acs_output_path
)

message("Saved ACS data to: ", acs_output_path)


# 9. Activate the FRED API key --------------------------------------------

fredr::fredr_set_key(fred_api_key)


# 10. Download mortgage-rate data from FRED -------------------------------

message("Downloading FRED mortgage-rate data...")

mortgage_raw <- fredr::fredr(
  series_id = "MORTGAGE30US",
  observation_start = as.Date("2019-01-01"),
  observation_end = as.Date("2024-12-31")
) |>
  transmute(
    date = as.Date(date),
    mortgage_rate = as.numeric(value)
  ) |>
  arrange(date)


# 11. Validate FRED data --------------------------------------------------

if (nrow(mortgage_raw) == 0) {
  stop("The FRED download returned no observations.")
}

if (all(is.na(mortgage_raw$mortgage_rate))) {
  stop("All downloaded mortgage-rate values are missing.")
}

if (
  min(mortgage_raw$date, na.rm = TRUE) <
  as.Date("2019-01-01") ||
  max(mortgage_raw$date, na.rm = TRUE) >
  as.Date("2024-12-31")
) {
  stop("The FRED data contain dates outside the requested period.")
}


# 12. Save raw FRED data --------------------------------------------------

mortgage_output_path <- paste0(
  "data/raw/",
  "fred_mortgage_rate_2019_2024.csv"
)

write_csv(
  mortgage_raw,
  mortgage_output_path
)

message(
  "Saved FRED data to: ",
  mortgage_output_path
)


# 13. Create a data-source reference file ---------------------------------

data_sources <- tibble::tribble(
  ~dataset, ~variable, ~description, ~source,
  "ACS 1-year estimates",
  "B19013_001E",
  "Median household income",
  "U.S. Census Bureau",
  "ACS 1-year estimates",
  "B19013_001M",
  "Margin of error for median household income",
  "U.S. Census Bureau",
  "ACS 1-year estimates",
  "B25077_001E",
  "Median value of owner-occupied housing units",
  "U.S. Census Bureau",
  "ACS 1-year estimates",
  "B25077_001M",
  "Margin of error for median home value",
  "U.S. Census Bureau",
  "FRED",
  "MORTGAGE30US",
  "30-year fixed-rate mortgage average in the United States",
  "Federal Reserve Bank of St. Louis"
)

write_csv(
  data_sources,
  "data/raw/data_sources.csv"
)


# 14. Display download summary --------------------------------------------

cat("\n")
cat("Download completed successfully.\n")
cat("--------------------------------\n\n")

cat("ACS observations by year:\n")

acs_raw |>
  count(year, name = "observations") |>
  print()

cat("\nACS missing-value summary:\n")
print(acs_missing_summary)

cat("\nMortgage-rate data summary:\n")

mortgage_raw |>
  summarise(
    first_date = min(date, na.rm = TRUE),
    last_date = max(date, na.rm = TRUE),
    observations = n(),
    missing_rates = sum(is.na(mortgage_rate)),
    minimum_rate = min(mortgage_rate, na.rm = TRUE),
    average_rate = mean(mortgage_rate, na.rm = TRUE),
    maximum_rate = max(mortgage_rate, na.rm = TRUE)
  ) |>
  print()

cat("\nRaw files created:\n")

list.files(
  path = "data/raw",
  full.names = TRUE
) |>
  print()