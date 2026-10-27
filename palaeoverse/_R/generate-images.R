# Load libraries
library(palaeoverse)
width = 2500
height = 1500
res = 300

# Latitudinal bins
png(filename = "palaeoverse/img/lat-bins.png",
    width = width, height = height, res = res)
lat_bins_area(n = 12, plot = TRUE)
dev.off()

# Temporal range
png(filename = "palaeoverse/img/temporal-range.png",
    width = width, height = height, res = res)
data(tetrapods)
tetrapods |>
  subset(!is.na(order)) |>
  tax_range_time(name = "order", plot = TRUE)
dev.off()


