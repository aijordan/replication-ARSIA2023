library(isotone)

# Compute reliability diagram
reldiag <- function(x, y, alpha = 0.5, resampling = TRUE, n_resamples = 99,
                    region_level = 0.9, resample_log = FALSE, digits = 2) {
  pava <- function(x, y) {
    # In case of ties, isotone::gpava uses the conditional mean instead of quantile, try e.g.,
    # gpava(c(-1,-1,-1),c(-1,0,0),solver = weighted.median,ties = "secondary")
    # New fix: Use ranking of predictor values and break ties by ordering the
    # corresponding instances in order of decreasing observations
    ranking <- match(1:length(x), order(x, y, decreasing = c(FALSE, TRUE)))
    gpava(ranking, y, solver = weighted.fractile, p = alpha, ties = "secondary")$x
  }
  score <- function(x, y) mean((as.numeric(x >= y) - alpha) * (x - y))
  marg <- function(x) quantile(x, alpha, type = 1)
  identif <- function(x, y) as.numeric(x > y) - alpha

  ord_x <- order(x)
  x <- x[ord_x]
  y <- y[ord_x]

  x_rc <- pava(x, y)

  res <- y - x

  s <- score(x, y)
  c_rc_ucond <- optim(par = 0, fn = function(c) score(x + c, y),
                      method = "Brent", lower = min(res), upper = max(res))$par
  s_rc_ucond <- score(x + c_rc_ucond, y)
  s_rc <- score(x_rc, y)
  s_mg <- score(marg(y), y)

  mcb <- s - s_rc
  umcb <- s - s_rc_ucond
  cmcb <- s_rc_ucond - s_rc
  dsc <- s_mg - s_rc
  unc <- s_mg

  # The Score is exactly equal to uMCB + cMCB - DSC + UNC.
  # However, when rounding the values there may be slight discrepancies between the rounded values.
  # We avoid this for didactic reasons by computing the score from the rounded values.
  s <- sum(round(c(umcb, cmcb, -dsc, unc), digits))

  # test: mean identification zero? (t-test)
  # v = identif(x,y)
  # t = sqrt(length(v)) * mean(v)/sd(v)
  # pval_ucond = 1 - abs(pt(t,length(v)-1) - 0.5)*2

  # Unconditional calibration test
  # Coverage test: One-sided Binomial tests with Bonferroni correction
  eps <- 10^-10 # avoid numerical artifacts by assuming that values with an
                # absolute difference of less than eps are identical
  hard_cov <- sum(y < x - eps)
  soft_cov <- sum(y < x + eps)

  pval_hard <- dbinom(hard_cov, length(y), alpha) + pbinom(hard_cov, length(y), alpha, FALSE)
  pval_soft <- pbinom(soft_cov, size = length(y), prob = alpha)
  pval_ucond <- min(pval_hard, pval_soft, 0.5) * 2
  # print(paste0("p-Values: hard ",pval_hard,", soft ",pval_soft))

  if (resampling) {
    n_samples <- n_resamples + 1 # total number of samples including observed sample
    low <- floor(n_samples * (1 - region_level) / 2)
    up <- n_samples - low
    pval_digits <- ceiling(log(n_samples, 10))

    if (resample_log) {
      res_log <- log(y) - log(x)
      resamples <- sapply(1:n_resamples, function(i) exp(log(x) + sample(res_log, length(y), replace = TRUE)))
    } else {
      resamples <- sapply(1:n_resamples, function(i) x + sample(res, length(y), replace = TRUE))
    }

    x_rc_resamples <- apply(resamples, 2, function(y) pava(x, y))
    x_rc_resamples_sorted <- apply(cbind(x_rc, x_rc_resamples), 1, sort) - marg(res)
                             # includes observed values + bias corrected (shifted by mean residual)

    ran_x <- range(x)

    mcb_resamples <- sapply(1:n_resamples, function(i) score(x, resamples[, i]) - score(x_rc_resamples[, i], resamples[, i]))
    mcb_bounds <- sort(c(mcb, mcb_resamples))[c(low, up)]

    rank_obs <- tail(rank(c(mcb_resamples, mcb)), 1)
    pval <- 1 - (rank_obs - 1) / (n_resamples + 1)

    lower <- x_rc_resamples_sorted[low, ]
    upper <- x_rc_resamples_sorted[up, ]
  } else {
    lower <- NA
    upper <- NA
    pval <- NA
  }

  results <- data.frame(
    quantile = alpha, x = x, y = y, x_rc = x_rc,
    lower = lower, upper = upper,
    digits = digits, score = s,
    umcb = umcb, cmcb = cmcb, mcb = mcb, dsc = dsc, unc = unc,
    pval_cond = pval, pval_ucond = pval_ucond
  )
}



# Plot reliability diagram
plot_reldiag <- function(df_reldiag,
                         score_decomp = TRUE,
                         pval = TRUE,
                         my_alpha = 0.3) {
  if (score_decomp) {
    digits_f <- paste0("%.", df_reldiag$digits[1], "f")
    scores <- df_reldiag %>%
      distinct(across(score:pval_ucond)) %>%
      mutate(label = paste0(
        c("\nuMCB ", "cMCB ", "DSC ", "UNC "),
        sprintf(digits_f, c(umcb, cmcb, dsc, unc)),
        if (pval) c(sprintf(" [p = %.2f]", c(pval_ucond, pval_cond)), "", ""),
        collapse = "\n"
      ))
    score_layer <- list(
      geom_label(
        aes(x = -Inf, y = Inf, label = sprintf("bar(S)~'%s'", sprintf(digits_f, score))),
        data = scores, size = 6 * 0.36, hjust = 0, vjust = 1, label.size = NA,
        alpha = 0, label.padding = unit(1, "lines"), parse = TRUE
      ),
      geom_label(
        mapping = aes(x = -Inf, y = Inf, label = label),
        data = scores, size = 6 * 0.36, hjust = 0, vjust = 1, label.size = NA,
        alpha = 0, label.padding = unit(1, "lines"), parse = FALSE
      )
    )
  } else {
    score_layer <- list()
  }

  # needed to ensure square facets with equal x and y limits
  facet_lims <- df_reldiag %>%
    summarize(
      mn = min(c_across(c(x, x_rc, lower, upper))),
      mx = max(c_across(c(x, x_rc, lower, upper))),
      .groups = "keep"
    )

  ggplot(df_reldiag, aes(x, x_rc, group = model)) +
    geom_point(aes(x, y), alpha = my_alpha, size = 0.1) +
    geom_abline(intercept = 0, slope = 1, colour = "grey70") +
    geom_ribbon(aes(ymin = lower, ymax = upper),
                color = "skyblue3", size = 0.35,
                fill = "skyblue3", alpha = 0.4) +
    geom_line(color = "firebrick3") +
    geom_blank(data = facet_lims, aes(x = mx, y = mx)) +
    geom_blank(data = facet_lims, aes(x = mn, y = mn)) +
    xlab("Forecast value") +
    ylab("Conditional quantile") +
    scale_x_continuous(guide = guide_axis(check.overlap = TRUE)) +
    theme_bw(base_size = 11) +
    coord_fixed() +
    theme(
      panel.grid.major = element_line(size = 0.05),
      panel.grid.minor = element_line(size = 0.05),
      strip.text.x = element_text(size = 7),
      strip.text.y = element_text(size = 7),
    ) +
    score_layer
}
