#' @title lineplotFSDP
#' @description Line plots FSDP
#'
#' @export
#'
#' @param repReg rds file or data.frame with all MAgPIE runs, produced with FSDP_collect.R output script.
#' @param val rds file or data.frame with validation data
#' @param regionSel Region that should be plotted (e.g. c("IND","EUR","GLO")). Aggregate will return LIR, MIR and HIR.
#' @param file file name
#' @param scens if "BAU_FSEC", BAU and FSEC scenarios are plotted, with "central" plots the core scenarios, "extended" plot the core scenarios and all ssps.
#' @details creates validation for FSDP MAgPIE runs
#' @return NULL
#' @author Florian Humpenoeder
#' @import ggplot2 data.table patchwork
#' @importFrom utils write.csv tail
#' @importFrom stats reorder

lineplotFSDP <- function(repReg, val, regionSel = "GLO", file = NULL, scens="bundles") {

  #### read in data files
  if(scens=="central"){
    rep <- convertReportFSDP(repReg, scengroup = c("FSECc", "FSECd","FSECe"), subset = FALSE)
    rep <- rep[rep$scenario %in%c("SSP1bau","SSP1PLUSbau", "SSP2bau", "SSP5bau", "FSDP"), ]
  } else if (scens=="BAU_FSEC") {
    rep <- convertReportFSDP(repReg, scengroup = c("FSECc","FSECe"), subset = FALSE)
  } else if (scens=="extended") {
    rep <- convertReportFSDP(repReg, scengroup = c("FSECc", "FSECd","FSECe"), subset = FALSE)
    rep <- rep[rep$scenario %in%c("SSP1bau","SSP1PLUSbau", "SSP2bau","SSP2fsdp","SSP3bau","SSP4bau", "SSP5bau", "FSDP"), ]
  } else if (scens=="bundles") {
    rep <- convertReportFSDP(repReg, scengroup = c("FSECa","FSECb","FSECc", "FSECd","FSECe"), subset = FALSE)
    scenOrder <- c("AgroMngmt","NatureSparing","Livelihoods","Sufficiency","ExternalPressures", "FSDP", "SSP2bau")
    rep <- rep[get("scenario") %in% scenOrder, ]
    rep$scenario <- factor(rep$scenario, scenOrder)
    #factor(rep[!scenario %in% c("SSP2bau","FSEC"),c("scenset")])
  } else {stop("unknown scens")}

  if (!is.data.frame(val)) val <- readRDS(val)
  val[region == "World", region := "GLO"]
  val <- droplevels(val)

  #needed for some nitrogen variables
  levels(rep$region)[levels(rep$region) == "World"] <- "GLO"

  #get variable list
  var <- getVariables(levels(rep$variable))

  renameRep <- function(rep,var,regionSel) {
    levels(rep$region)[levels(rep$region) == "World"] <- "GLO"
    rep$region <- factor(rep$region)
    rep <- rep[get("variable") %in% var & get("region") == regionSel, ]
    rep <- droplevels(rep)

    rep$variable <- factor(rep$variable, levels = var, labels = names(var))
    rep[, c("vargroup", "order", "variable", "unit", "improvment", "rounding","factor") := tstrsplit(get("variable"), "|", fixed = TRUE)]
    rep$order <- as.numeric(rep$order)
    rep$rounding <- as.numeric(rep$rounding)
    rep$factor <- as.numeric(rep$factor)

    vargroupOrder <- c("Health", "Environment", "Inclusion", "Economy")
    rep$vargroup <- factor(rep$vargroup, levels = vargroupOrder)

    #rep$variable <- reorder(rep$variable, rep$order)
    rep[,"variableName" := paste(get("variable"),get("unit"),sep="\n")]
    rep$variable <- reorder(rep$variable, rep$order)

    rep$unit <- reorder(rep$unit, rep$order)

    rep[,"value" := get("value") * get("factor")]

    return(rep)
  }
  rep <- renameRep(rep,var,regionSel)
  rep[get("scenset") %in% c("FSECd","FSECe"), "scenset" := "SSP2bau / FSDP"]
  rep[get("scenset") %in% c("FSECb"), "scenset" := "Bundles"]
  rep$scenset <- factor(rep$scenset, c("SSP2bau / FSDP", "Bundles"))

  val <- renameRep(val,var,regionSel)

  safe_colorblind_palette <- assignScenarioColors(scenOrder)
  names(safe_colorblind_palette) <- scenOrder

  #override.linetype <- c(3,3,3,3,3,1,1)
  override.linetype <- rev(c("dashed","dashed","dashed","dashed","dashed","solid","solid"))
  names(override.linetype) <- scenOrder

  themeMy <- function(baseSize = 13, baseFamily = "", rotateX = FALSE, panelSpacing = 3) {
    txt <- element_text(size = baseSize, colour = "black", face = "plain")
    boldTxt <- element_text(size = baseSize, colour = "black", face = "bold")

    theme_bw(base_size = baseSize, base_family = baseFamily) +
      theme(
        legend.key = element_blank(),
        strip.background = element_rect(color = "black", fill = "grey95"),
        axis.text.x = if (rotateX) element_text(angle = 90, hjust = 1, vjust = 0.5) else element_text(angle = 0, hjust = 0.5, vjust = 0),
        axis.title.x = element_text(vjust = 0),
        axis.title.y = element_text(margin = margin(t = 0, r = 5, b = 0, l = 0)),
        axis.title.y.right = element_text(margin = margin(t = 0, r = 0, b = 0, l = 5)),
        panel.grid.minor.x = element_blank(),
        panel.grid.major.x = element_blank(),

        panel.spacing.x = unit(panelSpacing, "mm"),
        panel.spacing.y = unit(panelSpacing, "mm"),

        # text = txt,
        plot.title = txt,
        #
        # axis.title = txt,
        # axis.text = txt,

        legend.text = element_text(margin = margin(r = 10), hjust = 0, size = baseSize,
                                   colour = "black", face = "plain"),
        legend.title = element_text(margin = margin(r = 10), hjust = 0, size = baseSize,
                                    colour = "black", face = "bold")
      ) + theme(legend.position = "bottom", legend.box = "horizontal", legend.title.align = 0)
  }

  if (all(length(regionSel) == 1 & regionSel == "aggregate")) {
    #### mapping for regional aggregation
    map <- data.frame(matrix(nrow = 15, ncol = 2))
    names(map) <- c("region", "region_class")
    map[1, ] <- c("ANZ", "HIR")
    map[2, ] <- c("BRA", "MIR")
    map[3, ] <- c("CAN", "HIR")
    map[4, ] <- c("CHA", "MIR")
    map[5, ] <- c("EUR", "HIR")
    map[6, ] <- c("IND", "LIR")
    map[7, ] <- c("JKO", "HIR")
    map[8, ] <- c("LAM", "MIR")
    map[9, ] <- c("MEA", "MIR")
    map[10, ] <- c("NEA", "MIR")
    map[11, ] <- c("NEU", "MIR")
    map[12, ] <- c("OAS", "MIR")
    map[13, ] <- c("SSA", "LIR")
    map[14, ] <- c("USA", "HIR")
    map[15, ] <- c("GLO", "GLO")
    rep <- merge(rep, map)
    val <- merge(val, map)

    regSubOrder <- c("LIR", "MIR", "HIR", "GLO")
    rep$region_class <- factor(rep$region_class, levels = regSubOrder)
    val$region_class <- factor(val$region_class, levels = regSubOrder)

    rep <- rep[rep$region_class != "GLO", ]
    val <- val[val$region_class != "GLO", ]

  } else {

    rep$region_class <- rep$region
    val$region_class <- val$region
    rep <- rep[rep$region_class %in% regionSel, ]
    val <- val[val$region_class %in% regionSel, ]

  }

  # plot function
  plotVal <- function(rep,var, units = NULL, varName = NULL, unitName = NULL, weight = NULL, hist = NULL, histName = NULL, tag = NULL, showlegend = FALSE) {
    empty2null<-function(x){out<-x; if(!is.null(x)){if(any(x=="empty")){out<-NULL}}; return(out)}
    varName=empty2null(varName)
    weight=empty2null(weight)
    hist=empty2null(hist)
    units=empty2null(units)
    unitName=empty2null(unitName)
    histName=empty2null(histName)
    tag=empty2null(tag)

    if (var %in% rep$variable){
      if (is.null(units)) {
        units <- levels(rep$unit)
      }
      b <- rep[rep$variable == var & rep$unit %in% units & rep$period >= 2000 & rep$period <= 2050, ]
      b <- droplevels(b)
      units <- levels(b$unit)
      unitHist <- levels(val$unit)[grep(units, levels(val$unit), fixed = TRUE)][1]
      if (is.null(hist)) {
        h <- val[val$variable == var & val$unit == unitHist & val$scenario == "historical" &
                   val$period >= 2000 & val$period <= 2020, ]
      } else {
        h <- val[val$variable == var & val$unit == unitHist & val$scenario == "historical" &
                   val$period >= 2000 & val$period <= 2020 & val$model %in% hist, ]
        h <- droplevels(h)
        if (!is.null(histName)) {
          h$model <- factor(h$model,hist,histName)
        }
      }

      if (!is.null(weight)) {
        w1 <- rep[rep$variable == weight & rep$period >= 2000 & rep$period <= 2050, ]
        w2 <- val[val$variable == weight & val$scenario == "historical" &
                    val$period >= 2000 & val$period <= 2020, ]
        b <- cbind(b, w1$value)
        h <- cbind(h, w2$value)
        b <- b[, list(value = weighted.mean(get("value"), get("V2"))),
               by = c("region_class", "model", "scenset", "scenario", "variable", "unit", "period")]
        h <- h[, list(value = weighted.mean(get("value"), get("V2"))),
               by = c("region_class", "model", "scenario", "variable", "unit", "period")]
      } else {
        b <- b[, list(value = sum(get("value"))),
               by = c("region_class", "model", "scenset", "scenario", "variable", "unit", "period")]
        h <- h[, list(value = sum(get("value"))),
               by = c("region_class", "model", "scenario", "variable", "unit", "period")]
      }

      if (is.null(varName)) varName <- var
      if (is.null(unitName)) unitName <- units

      p <- ggplot(b, aes(x = get("period"), y = get("value")))
      p <- p + labs(title = varName, tag = tag) + ylab(unitName) + xlab(NULL) + themeMy(rotateX = 0)
      p <- p + geom_line(aes(color = get("scenario"), linetype = get("scenset")), size = 1) #+ facet_wrap("region_class")
      p <- p + scale_x_continuous(NULL,breaks = c(2000,2025,2050), expand = c(0,0)) +
        scale_y_continuous(expand = expansion(mult = c(0, 0.05)), limits = c(0, NA)) + theme(plot.margin = margin(0, 20, 20, 0, "pt"))
      if (nrow(h) > 0) p <- p + geom_point(data = h, aes(shape = get("model")), size = 1)
      #p <- p + geom_line(data = b[get("scenset") == "Bundles",],aes(color = get("scenario")),linetype="dotted") #+ facet_wrap("region_class")
      #p <- p + geom_line(data = b[get("scenset") == "SSP2bau / FSDP",],aes(color = get("scenario")),linetype="solid") #+ facet_wrap("region_class")
      p <- p + scale_shape_discrete("Historical data", solid = 0)
      #p <- p + scale_color_brewer("MAgPIE scenario", palette = "Set2")
      p <- p + scale_color_manual("MAgPIE scenario", values = safe_colorblind_palette)
      # p <- p + theme(plot.caption = element_text(hjust = 1, face= "italic"), #Default is hjust=1
      #                plot.tag.position = "plot", #NEW parameter. Apply for subtitle too.
      #                plot.title.position = "plot", #NEW parameter. Apply for subtitle too.
      #                plot.caption.position =  "plot") #NEW parameter
      p <- p + theme(plot.tag = element_text(size = 13, margin = margin(b = -8.5, unit = "pt")))
      if (showlegend) {
        p <- p + theme(legend.key.width = unit(1.9,"cm"))
        p <- p + guides(color = guide_legend(order = 1, title.position = "top",ncol = 1, title = "Scenario", override.aes = list(linetype = override.linetype,size = 1), reverse = TRUE),
                        shape = guide_legend(order = 2, title.position = "top",ncol = 1, title = "Scenario"),
                        linetype = "none")
      } else {
        p <- p + guides(color = "none",
                        shape = "none",
                        linetype = "none")
      }
      return(p)
    } else {
      warning(paste0("Missing Variable: ",var))
      return(NULL)
    }

  }

  #todo: loop over variables. use variable Names from getVariables.
  p1 <- plotVal(rep, var = "Underweight", tag = "a)", showlegend = TRUE)
  p2 <- plotVal(rep, var = "Obesity", tag = "b)")
  p3 <- plotVal(rep, var = "Years of life lost", tag = "c)")

  p10 <- plotVal(rep, var = "Expenditures for agri.", tag = "d)")
  p11 <- plotVal(rep, var = "People Below 3.20$/Day", tag = "e)")
  p12 <- plotVal(rep, var = "Agri. employment", tag = "f)")
  p13 <- plotVal(rep, var = "Agri. wages", tag = "g)")

  p4 <- plotVal(rep, var = "Biodiversity", tag = "h)")
  p5 <- plotVal(rep, var = "Croparea diversity", tag = "i)")
  p6 <- plotVal(rep, var = "Nitrogen surplus", tag = "j)")
  p7 <- plotVal(rep, var = "Water flow violations", tag = "k)")
  p8 <- plotVal(rep, var = "Greenhouse Gases", tag = "l)")
  p9 <- plotVal(rep, var = "Global Surface Temp.", tag = "m)")

  p14 <- plotVal(rep, var = "Bioeconomy Supply", tag = "n)")
  p15 <- plotVal(rep, var = "Costs", tag = "o)")

  group1 <- p1 + p2 + p3 + guide_area() + plot_annotation(title = "Health", theme = theme(title = element_text(face="bold"), plot.background = element_rect(colour = "black", fill=NA, linewidth=2))) + plot_layout(guides = "collect", ncol = 2) & theme(legend.position = "bottom")
  group2 <- p4 + p5 + p6 + p7 + p8 + p9 + plot_annotation(title = "Environment", theme = theme(title = element_text(face="bold"), plot.background = element_rect(colour = "black", fill=NA, linewidth=2))) + plot_layout(guides = "collect", ncol = 2) & theme(legend.position = "none")
  group3 <- p10 + p11 + p12 + p13 + plot_annotation(title = "Inclusion", theme = theme(title = element_text(face="bold"), plot.background = element_rect(colour = "black", fill=NA, linewidth=2))) + plot_layout(guides = "collect", ncol = 2) & theme(legend.position = "none")
  group4 <- p14 + p15 + plot_annotation(title = "Economy", theme = theme(title = element_text(face="bold"), plot.background = element_rect(colour = "black", fill=NA, linewidth=2))) + plot_layout(guides = "collect", ncol = 2) & theme(legend.position = "none")

  col1 <- wrap_plots(wrap_elements(group1),wrap_elements(group3),ncol = 1,nrow=2,heights = c(0.5,0.5)) & theme(plot.margin = margin(0, 0, 10, 0, "pt"))
  col2 <- wrap_plots(wrap_elements(group2),wrap_elements(group4),ncol = 1,nrow=2,heights = c(0.73,0.27 )) & theme(plot.margin = margin(0, 0, 10, 0, "pt"))
  combined <- wrap_plots(wrap_elements(col1),wrap_elements(col2))

  if(!is.null(file)) {
    ggsave(file, combined, scale = 1, width = 13, height = 12, bg = "white")
    ggsave(paste0(substring(file, 1, nchar(file) - 3), "pdf"), combined, scale = 1, width = 13, height = 12, bg = "white")
  } else {
    return(combined)
  }

}
