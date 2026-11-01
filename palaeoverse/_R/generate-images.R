# Load libraries
library(palaeoverse)
width <- 2500
height <- 1500
res <- 300

# Margins: c(bottom, left, top, right)
mar <- c(4, 4, 2, 1)

# Latitudinal bins
png(filename = "palaeoverse/img/lat-bins.png",
    width = width, height = height, res = res,
    bg = "transparent", type = "cairo")
par(mar = mar)
lat_bins_area(n = 12, plot = TRUE)
dev.off()

# Temporal range
data(tetrapods)
png(filename = "palaeoverse/img/temporal-range.png",
    width = width, height = height, res = res,
    bg = "transparent", type = "cairo")
par(mar = mar)
tetrapods |>
  subset(!is.na(order)) |>
  tax_range_time(name = "order", plot = TRUE)
dev.off()