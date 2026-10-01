# 03_create_visualizations.R
#
# Create and save three publication-ready visualizations.


# 1. Check and load packages ----------------------------------------------

required_packages <- c(
  "dplyr",
  "readr",
  "ggplot2",
  "scales",
  "ggrepel",
  "stringr",
  "usmap"
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
    "Install the following packages: ",
    paste(missing_packages, collapse = ", ")
  )
}

library(dplyr)
library(readr)
library(ggplot2)
library(scales)
library(ggrepel)
library(stringr)
library(usmap)


# 2. Read processed data --------------------------------------------------

state_data <- read_csv(
  paste0(
    "data/processed/",
    "state_housing_affordability_2019_2024.csv"
  ),
  show_col_types = FALSE
)

mortgage_annual <- read_csv(
  paste0(
    "data/processed/",
    "national_mortgage_rates_annual.csv"
  ),
  show_col_types = FALSE
)

if (nrow(state_data) != 51) {
  stop("Expected 51 state-level observations.")
}

dir.create(
  "output/figures",
  recursive = TRUE,
  showWarnings = FALSE
)


# 3. Extract mortgage rates -----------------------------------------------

mortgage_rate_2019 <- mortgage_annual |>
  filter(year == 2019) |>
  pull(average_mortgage_rate)

mortgage_rate_2024 <- mortgage_annual |>
  filter(year == 2024) |>
  pull(average_mortgage_rate)


# 4. Define captions ------------------------------------------------------

caption_1 <- str_wrap(
  paste0(
    "Source: U.S. Census Bureau, 2019 and 2024 ACS 1-year estimates. ",
    "Note: Positive values indicate that median home values rose ",
    "relative to median household income. Washington, D.C. is included ",
    "in the analysis but is not visible at this map scale."
  ),
  width = 115
)

caption_2 <- str_wrap(
  paste0(
    "Source: U.S. Census Bureau, 2019 and 2024 ACS 1-year estimates. ",
    "Note: States above the dashed line experienced faster growth in ",
    "median home values than in median household income."
  ),
  width = 105
)

caption_3 <- str_wrap(
  paste0(
    "Sources: U.S. Census Bureau ACS and FRED series MORTGAGE30US. ",
    "Note: The illustrative calculation assumes purchase at the median ",
    "home value, a 20% down payment, and a 30-year fixed-rate mortgage. ",
    "Property taxes, insurance, maintenance, and HOA costs are excluded."
  ),
  width = 115
)


# 5. Define common theme --------------------------------------------------

theme_blog <- theme_minimal(
  base_size = 12
) +
  theme(
    plot.title.position = "plot",
    plot.caption.position = "plot",
    
    plot.title = element_text(
      face = "bold",
      size = 16,
      margin = margin(b = 7)
    ),
    
    plot.subtitle = element_text(
      size = 11.5,
      color = "gray30",
      margin = margin(b = 12)
    ),
    
    plot.caption = element_text(
      size = 8.5,
      color = "gray40",
      hjust = 0,
      lineheight = 1.1,
      margin = margin(t = 14)
    ),
    
    plot.margin = margin(
      t = 14,
      r = 22,
      b = 18,
      l = 18
    ),
    
    axis.title = element_text(
      face = "bold",
      size = 11.5
    ),
    
    axis.text = element_text(
      color = "gray30"
    ),
    
    panel.grid.minor = element_blank(),
    
    legend.position = "bottom",
    
    legend.title = element_text(
      face = "bold"
    )
  )


# Figure 1: affordability-change map --------------------------------------

map_data <- state_data |>
  transmute(
    state = state_abbr,
    price_to_income_change
  )

figure_1 <- usmap::plot_usmap(
  regions = "states",
  data = map_data,
  values = "price_to_income_change",
  color = "white",
  linewidth = 0.35
) +
  scale_fill_gradient2(
    low = "#2166AC",
    mid = "#F7F7F7",
    high = "#B2182B",
    midpoint = 0,
    labels = label_number(
      accuracy = 0.1
    ),
    name = "Change in ratio"
  ) +
  guides(
    fill = guide_colorbar(
      title.position = "top",
      title.hjust = 0.5,
      barwidth = grid::unit(5.8, "cm"),
      barheight = grid::unit(0.35, "cm")
    )
  ) +
  labs(
    title = paste0(
      "Housing affordability deteriorated ",
      "across much of the United States"
    ),
    subtitle = paste0(
      "Change in median home-value-to-income ratio, ",
      "2019–2024"
    ),
    caption = caption_1
  ) +
  theme(
    plot.title.position = "plot",
    plot.caption.position = "plot",
    
    plot.title = element_text(
      face = "bold",
      size = 16,
      margin = margin(b = 7)
    ),
    
    plot.subtitle = element_text(
      size = 11.5,
      color = "gray30",
      margin = margin(b = 12)
    ),
    
    plot.caption = element_text(
      size = 8.5,
      color = "gray40",
      hjust = 0,
      lineheight = 1.1,
      margin = margin(t = 14)
    ),
    
    plot.margin = margin(
      t = 14,
      r = 22,
      b = 20,
      l = 18
    ),
    
    legend.position = "bottom",
    legend.direction = "horizontal",
    
    legend.title = element_text(
      face = "bold"
    )
  )

ggsave(
  filename = paste0(
    "output/figures/",
    "figure_1_affordability_change_map.png"
  ),
  plot = figure_1,
  width = 10,
  height = 7,
  dpi = 300,
  bg = "white"
)


# Figure 2: home-value versus income growth -------------------------------

label_states <- state_data |>
  arrange(
    desc(
      abs(growth_gap_percentage_points)
    )
  ) |>
  slice_head(n = 8)

figure_2 <- ggplot(
  state_data,
  aes(
    x = income_growth_pct,
    y = home_value_growth_pct
  )
) +
  geom_abline(
    intercept = 0,
    slope = 1,
    linewidth = 0.8,
    linetype = "dashed",
    color = "gray45"
  ) +
  geom_point(
    aes(color = census_region),
    size = 3.2,
    alpha = 0.85
  ) +
  ggrepel::geom_text_repel(
    data = label_states,
    aes(
      label = state_abbr,
      color = census_region
    ),
    size = 3.6,
    fontface = "bold",
    box.padding = 0.4,
    point.padding = 0.3,
    min.segment.length = 0,
    show.legend = FALSE,
    seed = 6400
  ) +
  scale_x_continuous(
    labels = label_number(
      suffix = "%",
      accuracy = 1
    ),
    expand = expansion(
      mult = c(0.05, 0.12)
    )
  ) +
  scale_y_continuous(
    labels = label_number(
      suffix = "%",
      accuracy = 1
    ),
    expand = expansion(
      mult = c(0.05, 0.12)
    )
  ) +
  scale_color_manual(
    values = c(
      "North Central" = "#59A14F",
      "Northeast" = "#4E79A7",
      "South" = "#E15759",
      "West" = "#F28E2B"
    ),
    name = "Census region"
  ) +
  labs(
    title = "Home values outpaced incomes in most states",
    subtitle = paste0(
      "Cumulative nominal growth in median home value and ",
      "median household income, 2019–2024"
    ),
    x = "Growth in median household income",
    y = "Growth in median home value",
    caption = caption_2
  ) +
  theme_blog

ggsave(
  filename = paste0(
    "output/figures/",
    "figure_2_home_value_vs_income_growth.png"
  ),
  plot = figure_2,
  width = 9,
  height = 7.4,
  dpi = 300,
  bg = "white"
)


# Figure 3: estimated mortgage burden -------------------------------------

top_burden_states <- state_data |>
  slice_max(
    order_by = mortgage_burden_2024,
    n = 15,
    with_ties = FALSE
  ) |>
  arrange(mortgage_burden_2024) |>
  mutate(
    state_name = factor(
      state_name,
      levels = state_name
    )
  )

figure_3 <- ggplot(
  top_burden_states,
  aes(y = state_name)
) +
  geom_segment(
    aes(
      x = mortgage_burden_2019,
      xend = mortgage_burden_2024,
      yend = state_name
    ),
    linewidth = 1.1,
    color = "gray75"
  ) +
  geom_point(
    aes(
      x = mortgage_burden_2019,
      color = "2019"
    ),
    size = 3.4
  ) +
  geom_point(
    aes(
      x = mortgage_burden_2024,
      color = "2024"
    ),
    size = 3.4
  ) +
  geom_text(
    aes(
      x = mortgage_burden_2024,
      label = paste0(
        round(mortgage_burden_2024),
        "%"
      )
    ),
    nudge_x = 1.6,
    size = 3.1,
    color = "#B2182B"
  ) +
  scale_color_manual(
    values = c(
      "2019" = "#4E79A7",
      "2024" = "#B2182B"
    ),
    name = NULL
  ) +
  scale_x_continuous(
    labels = label_number(
      suffix = "%",
      accuracy = 1
    ),
    expand = expansion(
      mult = c(0.03, 0.12)
    )
  ) +
  labs(
    title = paste0(
      "Higher prices and rates sharply increased ",
      "mortgage burdens"
    ),
    subtitle = paste0(
      "Fifteen highest 2024 estimates; the national ",
      "30-year mortgage rate rose from ",
      sprintf("%.2f%%", mortgage_rate_2019),
      " to ",
      sprintf("%.2f%%", mortgage_rate_2024)
    ),
    x = paste0(
      "Estimated annual principal and interest\n",
      "as a share of median household income"
    ),
    y = NULL,
    caption = caption_3
  ) +
  theme_blog +
  theme(
    panel.grid.major.y = element_blank()
  )

ggsave(
  filename = paste0(
    "output/figures/",
    "figure_3_mortgage_burden_comparison.png"
  ),
  plot = figure_3,
  width = 10,
  height = 8.7,
  dpi = 300,
  bg = "white"
)


# 6. Confirm outputs ------------------------------------------------------

cat("\n")
cat("Reformatted visualizations created successfully.\n")
cat("------------------------------------------------\n\n")

list.files(
  path = "output/figures",
  pattern = "\\.png$",
  full.names = TRUE
) |>
  print()