library(tidyverse)
library(geomtextpath)
library(ggrepel)
source("R/reliability_functions.R")

df <- read_csv("data/covid19-preprocessed.csv.gz", col_types = cols()) %>%
  filter(
    location != "US",
    quantile %in% c(0.25, 0.5, 0.75),
    !model %in% c("COVIDhub-4_week_ensemble", "COVIDhub_CDC-ensemble")
  )

# compute score decomposition
results <- df %>%
  group_by(model, quantile) %>%
  summarize(reldiag(value, truth, alpha = unique(quantile), resampling = FALSE, digits = 1))

scores <- results %>%
  group_by(quantile, model) %>%
  distinct(across(score:pval_ucond))

scores$quantile <- as.factor(scores$quantile)

# shorten model names to save space
scores$model <- ifelse(sapply(scores$model, grepl, pattern = "COVIDhub", USE.NAMES = FALSE),
                       scores$model,
                       sapply(strsplit(scores$model, "-"), `[[`, 1)
)
scores$model <- as.factor(scores$model)
scores$model <- fct_relevel(scores$model, "COVIDhub-baseline", "COVIDhub-ensemble", "KITmetricslab")

# define isolines
iso <- scores %>%
  group_by(quantile) %>%
  summarize(
    mcb_best = floor(min(mcb)),
    dsc_best = ceiling(max(dsc)),
    mcb_worst = ceiling(max(mcb)),
    dsc_worst = floor(min(dsc)),
    unc = unique(unc),
    score_best = mcb_best - dsc_best + unc,
    score_worst = mcb_worst - dsc_worst + unc,
    y_best = dsc_best - mcb_best,
    y_worst = dsc_worst - mcb_worst
  )

# facet_lims <- iso %>%
#   group_by(quantile) %>%
#   summarize(
#     x_lim = 1.25 * mcb_worst,
#     y_lim = 1.025 * dsc_best
#   )

iso <- iso %>%
  group_by(quantile) %>%
  summarize(
    intercept = seq(y_worst + unc %% 1, y_best + unc %% 1,
                    by = round((score_worst - score_best) / 8)
    ),
    slope = 1,
    unc = unique(unc),
    .groups = "drop"
  ) %>%
  mutate(
    score = (unc - intercept),
    label = score
  )

# manually remove scores from isolines if there is overlap
iso$label[c(
  1, 2, 4, 8, 9, 10,
  13, 16, 18,
  20, 24, 27, 28
)] <- NA

ggplot(data = scores) +
  facet_wrap("quantile", scales = "free", ncol = 3) +
  # geom_blank(data = facet_lims, aes(x = x_lim, y = y_lim)) +
  geom_abline(
    data = iso, aes(intercept = intercept, slope = slope), color = "lightgray", alpha = 0.5,
    size = 0.5
  ) +
  geom_labelabline(
    data = iso, aes(intercept = intercept, slope = slope, label = label), color = "gray50",
    hjust = 0.85, size = 7 * 0.36, text_only = TRUE, boxcolour = NA, straight = TRUE
  ) +
  geom_point(aes(x = mcb, y = dsc, color = model), size = 0.4) +
  geom_text_repel(aes(x = mcb, y = dsc, label = model),
                  max.overlaps = NA, size = 8 * 0.36, nudge_x = 0,
                  direction = "both", segment.color = "transparent", box.padding = 0.15, force = 1, point.padding = 0.75,
                  seed = 4
  ) +
  xlab("MCB") +
  ylab("DSC") +
  theme_bw(base_size = 11) +
  theme(
    panel.grid.major = element_blank(),
    panel.grid.minor = element_blank(),
    aspect.ratio = 1,
    legend.position = "none",
    axis.text.x = element_blank(),
    axis.ticks.x = element_blank(),
    axis.text.y = element_blank(),
    axis.ticks.y = element_blank()
  ) +
  scale_color_brewer(palette = "Set1")

# ggsave("figures/06_score_decomposition_states.pdf", width = 160, height = 70, unit = "mm", device = "pdf")
