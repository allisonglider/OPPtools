#' Generate reports for central place foraging species tracked in OPP
#'
#' @description This function passes a table of parameters to an RMarkdown template to generate summary
#' reports on tracking data analysis.
#'
#' @param analysis_table Data frame that proivdes all values needed for the RMarkdown template, see details.
#' Defaults to the cpf_report_params data object that is contained within OPPTools.
#' @param login Stored Movebank login credentials if provided, otherwise function
#'will prompt users to enter credentials.
#' @param output_dir Name of of the directory where reports should be saved.
#'
#' @details Still need to write this up, once function is complete...
#'
#' The example below will only work if the user has permissions for all the projects listed in cpf_report_params
#'
#' @examples
#'
#' print(cpf_report_params)
#' opp_reports_cpf()
#'
#'@export

opp_reports_cpf <- function(analysis_table = cpf_report_params,login = NULL, output_dir = 'temp') {

  if (is.null(login)) login <- move::movebankLogin()

  for (i in 1:nrow(analysis_table)) {

    dat <- analysis_table[i,]

    rmarkdown::render(input = "inst/rmarkdown/templates/report_pdf/opp_cpf_report_template.Rmd",
                      output_format = "pdf_document",
                      output_file = paste0(dat$file_name, ".pdf"),
                      output_dir = output_dir)

  }
}

