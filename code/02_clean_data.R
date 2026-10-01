# 02_clean_data.R
#
# Project:
# Priced Out: How Did Housing Affordability Change
# Across U.S. States from 2019 to 2024?
#
# Purpose:
# 1. Clean the ACS and FRED raw data.
# 2. Remove Puerto Rico while retaining the 50 states and Washington, D.C.
# 3. Calculate price-to-income ratios and growth rates.
# 4. Estimate an illustrative mortgage-payment burden.
# 5. Save the processed datasets in data/processed/.


# 1. Check required packages ----------------------------------------------

required_packages <- c(
  "dplyr",
  "tidyr",
  "readr",
  "tibble"
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
library(tidyr)
library(readr)
library(tibble)


# 3. Confirm required raw files exist -------------------------------------

acs_input_path <- paste0(
  "data/raw/",
  "acs_state_housing_income_2019_2024.csv"
)

mortgage_input_path <- paste0(
  "data/raw/",
  "fred_mortgage_rate_2019_2024.csv"
)

required_files <- c(
  acs_input_path,
  mortgage_input_path
)

missing_files <- required_files[
  !file.exists(required_files)
]

if (length(missing_files) > 0) {
  stop(
    "The following raw files are missing: ",
    paste(missing_files, collapse = ", "),
    ". Run code/01_download_data.R first."
  )
}


# 4. Read raw data --------------------------------------------------------

acs_raw <- read_csv(
  acs_input_path,
  col_types = cols(
    year = col_integer(),
    state_fips = col_character(),
    state_name = col_character(),
    median_household_income = col_double(),
    income_moe = col_double(),
    median_home_value = col_double(),
    home_value_moe = col_double()
  )
)

mortgage_raw <- read_csv(
  mortgage_input_path,
  col_types = cols(
    date = col_date(),
    mortgage_rate = col_double()
  )
)


# 5. Create state lookup table --------------------------------------------

state_lookup <- tibble(
  state_name = c(
    state.name,
    "District of Columbia"
  ),
  state_abbr = c(
    state.abb,
    "DC"
  ),
  census_region = c(
    as.character(state.region),
    "South"
  )
)


# 6. Clean ACS data -------------------------------------------------------

acs_clean <- acs_raw |>
  # Puerto Rico has FIPS code 72.
  filter(state_fips != "72") |>
  inner_join(
    state_lookup,
    by = "state_name"
  ) |>
  arrange(year, state_name)


# 7. Validate cleaned ACS data --------------------------------------------

acs_counts <- acs_clean |>
  count(year, name = "observations")

if (!all(acs_counts$observations == 51)) {
  stop(
    "Expected 51 observations per year after excluding Puerto Rico."
  )
}

if (
  any(
    acs_clean$median_household_income <= 0,
    na.rm = TRUE
  )
) {
  stop(
    "The ACS data contain nonpositive household-income values."
  )
}

if (
  any(
    acs_clean$median_home_value <= 0,
    na.rm = TRUE
  )
) {
  stop(
    "The ACS data contain nonpositive home-value observations."
  )
}

if (
  anyNA(acs_clean$median_household_income) ||
  anyNA(acs_clean$median_home_value)
) {
  stop(
    "The cleaned ACS data contain missing income or home-value values."
  )
}


# 8. Convert ACS data from long to wide -----------------------------------

acs_wide <- acs_clean |>
  select(
    state_fips,
    state_name,
    state_abbr,
    census_region,
    year,
    median_household_income,
    income_moe,
    median_home_value,
    home_value_moe
  ) |>
  pivot_wider(
    names_from = year,
    values_from = c(
      median_household_income,
      income_moe,
      median_home_value,
      home_value_moe
    ),
    names_glue = "{.value}_{year}"
  )


# 9. Calculate annual average mortgage rates ------------------------------

mortgage_annual <- mortgage_raw |>
  mutate(
    year = as.integer(format(date, "%Y"))
  ) |>
  filter(year %in% c(2019, 2024)) |>
  group_by(year) |>
  summarise(
    average_mortgage_rate =
      mean(mortgage_rate, na.rm = TRUE),
    
    weekly_observations =
      sum(!is.na(mortgage_rate)),
    
    .groups = "drop"
  ) |>
  arrange(year)


# 10. Validate annual mortgage rates --------------------------------------

if (!all(c(2019, 2024) %in% mortgage_annual$year)) {
  stop(
    "Mortgage-rate data are missing for 2019 or 2024."
  )
}

mortgage_rate_2019 <- mortgage_annual |>
  filter(year == 2019) |>
  pull(average_mortgage_rate)

mortgage_rate_2024 <- mortgage_annual |>
  filter(year == 2024) |>
  pull(average_mortgage_rate)

if (
  length(mortgage_rate_2019) != 1 ||
  length(mortgage_rate_2024) != 1
) {
  stop(
    "Could not identify one annual mortgage rate for each year."
  )
}


# 11. Define mortgage-payment function ------------------------------------

calculate_monthly_payment <- function(
    home_value,
    annual_rate,
    down_payment_share = 0.20,
    mortgage_term_years = 30
) {
  
  principal <- home_value * (1 - down_payment_share)
  
  monthly_rate <- annual_rate / 100 / 12
  
  number_of_payments <- mortgage_term_years * 12
  
  principal *
    (
      monthly_rate *
        (1 + monthly_rate)^number_of_payments
    ) /
    (
      (1 + monthly_rate)^number_of_payments - 1
    )
}


# 12. Construct affordability measures ------------------------------------

state_affordability <- acs_wide |>
  mutate(
    # National mortgage rates are applied uniformly to every state.
    mortgage_rate_2019 = mortgage_rate_2019,
    mortgage_rate_2024 = mortgage_rate_2024,
    
    # Median home value divided by median household income.
    price_to_income_2019 =
      median_home_value_2019 /
      median_household_income_2019,
    
    price_to_income_2024 =
      median_home_value_2024 /
      median_household_income_2024,
    
    # Cumulative nominal growth from 2019 to 2024.
    home_value_growth_pct =
      100 * (
        median_home_value_2024 /
          median_home_value_2019 - 1
      ),
    
    income_growth_pct =
      100 * (
        median_household_income_2024 /
          median_household_income_2019 - 1
      ),
    
    # Positive values mean home values grew faster than income.
    growth_gap_percentage_points =
      home_value_growth_pct -
      income_growth_pct,
    
    # Change in the price-to-income ratio.
    price_to_income_change =
      price_to_income_2024 -
      price_to_income_2019,
    
    price_to_income_change_pct =
      100 * (
        price_to_income_2024 /
          price_to_income_2019 - 1
      ),
    
    # Estimated principal-and-interest payment under:
    # 20% down payment
    # 30-year fixed-rate mortgage
    monthly_payment_2019 =
      calculate_monthly_payment(
        home_value =
          median_home_value_2019,
        annual_rate =
          mortgage_rate_2019
      ),
    
    monthly_payment_2024 =
      calculate_monthly_payment(
        home_value =
          median_home_value_2024,
        annual_rate =
          mortgage_rate_2024
      ),
    
    # Annual principal-and-interest payments as a percentage
    # of annual median household income.
    mortgage_burden_2019 =
      100 * (
        monthly_payment_2019 * 12 /
          median_household_income_2019
      ),
    
    mortgage_burden_2024 =
      100 * (
        monthly_payment_2024 * 12 /
          median_household_income_2024
      ),
    
    mortgage_burden_change =
      mortgage_burden_2024 -
      mortgage_burden_2019,
    
    # Rank 1 represents the least affordable state/DC.
    affordability_rank_2024 =
      min_rank(
        desc(price_to_income_2024)
      ),
    
    mortgage_burden_rank_2024 =
      min_rank(
        desc(mortgage_burden_2024)
      )
  ) |>
  arrange(
    affordability_rank_2024,
    state_name
  )


# 13. Final validation ----------------------------------------------------

if (nrow(state_affordability) != 51) {
  stop(
    "The processed dataset should contain 51 observations."
  )
}

key_metrics <- state_affordability |>
  select(
    price_to_income_2019,
    price_to_income_2024,
    home_value_growth_pct,
    income_growth_pct,
    monthly_payment_2019,
    monthly_payment_2024,
    mortgage_burden_2019,
    mortgage_burden_2024
  )

if (anyNA(key_metrics)) {
  stop(
    "One or more constructed affordability measures are missing."
  )
}

if (
  any(
    state_affordability$mortgage_burden_2019 <= 0
  ) ||
  any(
    state_affordability$mortgage_burden_2024 <= 0
  )
) {
  stop(
    "One or more mortgage-burden estimates are nonpositive."
  )
}


# 14. Save processed datasets ---------------------------------------------

state_output_path <- paste0(
  "data/processed/",
  "state_housing_affordability_2019_2024.csv"
)

mortgage_output_path <- paste0(
  "data/processed/",
  "national_mortgage_rates_annual.csv"
)

write_csv(
  state_affordability,
  state_output_path
)

write_csv(
  mortgage_annual,
  mortgage_output_path
)


# 15. Display processing summary ------------------------------------------

cat("\n")
cat("Data cleaning completed successfully.\n")
cat("-------------------------------------\n\n")

cat("ACS observations after excluding Puerto Rico:\n")
print(acs_counts)

cat("\nAnnual average 30-year mortgage rates:\n")
print(mortgage_annual)

cat("\nNational median across the 51 state-level observations:\n")

state_affordability |>
  summarise(
    median_price_to_income_2019 =
      median(price_to_income_2019),
    
    median_price_to_income_2024 =
      median(price_to_income_2024),
    
    median_home_value_growth_pct =
      median(home_value_growth_pct),
    
    median_income_growth_pct =
      median(income_growth_pct),
    
    median_mortgage_burden_2019 =
      median(mortgage_burden_2019),
    
    median_mortgage_burden_2024 =
      median(mortgage_burden_2024)
  ) |>
  print()

cat("\nTen states/DC with the highest 2024 price-to-income ratios:\n")

state_affordability |>
  select(
    state_name,
    price_to_income_2019,
    price_to_income_2024,
    price_to_income_change,
    mortgage_burden_2024
  ) |>
  slice_head(n = 10) |>
  print(n = 10)

cat("\nProcessed files created:\n")

list.files(
  path = "data/processed",
  full.names = TRUE
) |>
  print()