#!/usr/bin/env Rscript

options(repos = c(CRAN = "https://cloud.r-project.org/"))

library(ggplot2)
library(svglite)
library(ggrepel)
library(dplyr)
library(pander)


file_list <- list.files(path = "results/oltp_read_only_8thr_2m/", pattern = "\\.out$", full.names = TRUE)

results <- data.frame(
  commit = character(),
  date = as.POSIXct(character()),
  tps = numeric(),
  latency = numeric()
)

for (file_name in file_list) {
  commit_hash <- regmatches(file_name, regexec("([a-z0-9]{40})(_\\d)?\\.out", file_name))[[1]][2]
  datetime_str <- regmatches(file_name, regexec("([0-9]{8}-[0-9]{6})", file_name))[[1]][2]
  date <- as.POSIXct(datetime_str, format = "%Y%m%d-%H%M%S", tz = "UTC")

  content <- readLines(file_name)
  tps_line <- grep("events/s", content, value = TRUE)
  if (identical(tps_line, character(0))) {
    next
  }
  parts <- unlist(strsplit(tps_line, " "))
  tps <- as.numeric(parts[length(parts)])

  latency_line <- grep("99th", content, value = TRUE)
  parts <- unlist(strsplit(latency_line, " "))
  latency <- as.numeric(parts[length(parts)])

  results <- rbind(results, data.frame(commit = commit_hash, date = date, tps = tps, latency = latency))
}

results <- results %>%
  group_by(commit, date) %>%
  summarise(tps = median(tps),
            latency = median(latency),
            .groups = 'drop') %>%
  arrange(date)

sumSquaredError <- function(data) {
  avg <- mean(data)
  return(sum((data - avg)^2))
}

stepFit <- function(before, after) {
  totalSquaredError <- sumSquaredError(before) + sumSquaredError(after)
  stepError <- sqrt(totalSquaredError) / (length(before) + length(after))

  if (is.na(stepError) || stepError == 0) {
    return(0)
  }

  return((mean(before) - mean(after)) / stepError)
}

WIDTH <- 5
THRESHOLD <- 15
change_score <- c(rep(NA, length(results$latency)))
regressions_type <- c(rep(NA, length(results$latency)))

if (length(results$latency) >= WIDTH * 2) {
  for (i in ((WIDTH * 2):length(results$latency))) {
    data <- results$latency[(i - WIDTH * 2 + 1):i]
    score <- stepFit(
      before = data[1:WIDTH],
      after = data[(WIDTH + 1):(WIDTH * 2)]
    )

    change_score[i - WIDTH + 1] <- score
    if (abs(score) > THRESHOLD) {
      regressions_type[i - WIDTH + 1] <- if (score < 0) "REGRESSION" else "IMPROVEMENT"
    }
  }
}

results$change_score <- change_score
results$regressions_type <- regressions_type

choose_significant_changes <- function(results, change_type) {
  for (i in 1:length(results$regressions_type)) {
    if (!is.na(results$regressions_type[i])) {
      change_score <- results$change_score[i]
      change_indices <- i
      j <- i + 1

      while (!is.na(results$regressions_type[j])) {
        change_indices <- c(change_indices, j)
        change_score <- c(change_score, abs(results$change_score[j]))
        j <- j + 1
      }

      max_index <- change_indices[which.max(change_score)]

      for (k in change_indices) {
        if (k != max_index) {
          results$regressions_type[k] <- NA
        }
      }

      i <- j
    }
  }

  return(results)
}

results <- choose_significant_changes(results, "IMPROVEMENT")
results <- choose_significant_changes(results, "REGRESSION")

sink("results.md")
emphasize.strong.rows(which(!is.na(results$regressions_type)))
pandoc.table(results, style = "rmarkdown", split.table=160)
sink()


plot_and_save <- function(data, y_value, plot_title, y_label, file_name) {
  plot <- ggplot(data, aes(x = date, y = !!sym(y_value))) +
    geom_point() +
    labs(
      title = plot_title,
      x = "Commit date",
      y = y_label
    ) +
    theme_minimal() +
    theme(plot.background = element_rect(fill="white", colour = "white"))

  regression_lines <- data[data$regressions_type == "REGRESSION", ]
  improvement_lines <- data[data$regressions_type == "IMPROVEMENT", ]

  plot <- plot +
    geom_vline(data = regression_lines, aes(xintercept = as.numeric(date)), color = "red", linetype = "dashed", na.rm = TRUE) +
    geom_vline(data = improvement_lines, aes(xintercept = as.numeric(date)), color = "green", linetype = "dashed", na.rm = TRUE)

  plot <- plot +
    geom_text_repel(data = regression_lines, aes(x = date, y = max(data[[y_value]]) * 0.95, label = substring(commit, 1, 9), angle = 0), hjust = 0, size = 3, color = "red", na.rm = TRUE) +
    geom_text_repel(data = improvement_lines, aes(x = date, y = max(data[[y_value]]) * 0.95, label = substring(commit, 1, 9), angle = 0), hjust = 0, size = 3, color = "green", na.rm = TRUE)

  ggsave(file_name, device = "svg", width = 14, height = 7)
}

plot_and_save(results, "tps", "TPS", "TPS", "tps.svg")
plot_and_save(results, "latency", "99th latency", "Latency", "latency.svg")
