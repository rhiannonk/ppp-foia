# --- R code for a basic exploratory analysis of PPP FOIA loan data

# Download and clean PPP FOIA loan datasets for analysis

data_path <- "data"

# Latest PPP FOIA datasets available from the U.S. Small Business
# Administration (https://data.sba.gov/dataset/ppp-foia)
loan_files <- c(
  "public_150k_plus_230630.csv",
  "public_up_to_150k_1_230630.csv",
  "public_up_to_150k_2_230630.csv",
  "public_up_to_150k_3_230630.csv",
  "public_up_to_150k_4_230630.csv",
  "public_up_to_150k_5_230630.csv",
  "public_up_to_150k_6_230630.csv",
  "public_up_to_150k_7_230630.csv",
  "public_up_to_150k_8_230630.csv",
  "public_up_to_150k_9_230630.csv",
  "public_up_to_150k_10_230630.csv",
  "public_up_to_150k_11_230630.csv",
  "public_up_to_150k_12_230630.csv"
)

read_file <- function(file_name){
  file_path <- file.path(getwd(), data_path, file_name)
  readr::read_csv(file_path)
}

# Labels for highest-level NAICS classifications
naics_labels <- read.csv(file.path(data_path, "NAICS_labels.csv"))

naics_raw <- readxl::read_xlsx(
    file.path(data_path, "2022_NAICS_Descriptions.xlsx")
  ) %>% 
  dplyr::mutate(Title = substr(Title, 1, nchar(Title) - 1))

# Professional, scientific, and technical services subcategories (2 levels down)
subgroups <- dplyr::filter(naics_raw, substr(Code, 1, 2) == "54" & 
    nchar(Code) %in% c(4,5,6)
  ) %>% 
  dplyr::mutate(
    sublevel = dplyr::case_when(
      nchar(Code) == 4 ~ "Level 1", 
      nchar(Code) == 5 ~ "Level 2",
      nchar(Code) == 6 ~ "Level 3",
      TRUE ~ ""
      ),
    Code = as.integer(Code),
    Title_Subgroup1 = Title,
    Title_Subgroup2 = Title,
    Title_Subgroup3 = Title
  )

loan_data_raw <- lapply(loan_files, read_file) %>% 
  do.call(rbind, .) %>% 
  dplyr::select(LoanNumber, NAICSCode, NonProfit, CurrentApprovalAmount) %>% 
  dplyr::mutate(
    NonProfitNew = dplyr::if_else(NonProfit == "Y", "Nonprofit", "Other", "Other"),
    # Extract 2 and 3-digit NAICS codes for mapping industry labels
    NAICSCode_2digit = as.integer(substr(NAICSCode, 1, 2)),
    NAICSCode_4digit = as.integer(substr(NAICSCode, 1, 4)),
    NAICSCode_5digit = as.integer(substr(NAICSCode, 1, 5))
  ) %>% 
  # Merge industry labels
  dplyr::left_join(naics_labels, by = c("NAICSCode_2digit" = "Code")) %>% 
  dplyr::left_join(
    select(subgroups, Code, Title_Subgroup1), 
    by = c("NAICSCode_4digit" = "Code")
  ) %>% 
  dplyr::left_join(
    select(subgroups, Code, Title_Subgroup2), 
    by = c("NAICSCode_5digit" = "Code")
  )

# We see all non-linked NAICS codes had either an NA or 999990 original code
# filter(loan_data, is.na(Title)) %>% select(NAICSCode) %>% distinct() 
saveRDS(loan_data_raw, file.path(data_path, "loan_data.rds"), compress = FALSE)

# Sumamrize by non-profit status and high-level industry classification

# Number of loans
loans_by_sector <- loan_data_raw %>% 
  dplyr::count(Title, NonProfitNew) %>% 
  tidyr::pivot_wider(id_cols = Title, names_from = NonProfitNew, values_from = n) %>% 
  rename(`Economic sector` = Title) %>% 
  dplyr::mutate(
    `Economic sector` = if_else(is.na(`Economic sector`), "Not reported", `Economic sector`),
    Total = Nonprofit + Other
  ) %>% 
  dplyr::arrange(desc(Total)) %>% 
  dplyr::select(`Economic sector`, Other, Nonprofit)

write_csv(data.frame(loans_by_sector), file = file.path(data_path, "loans_by_sector.csv"))

# Dollars
dollars_by_sector <- loan_data_raw %>% 
  dplyr::group_by(Title) %>% 
  dplyr::summarize(
    Dollars = sum(CurrentApprovalAmount),
    Forgiven = sum(ForgivenessAmount, na.rm = TRUE)
  ) %>% 
  dplyr::mutate(Paid = Forgiven / Dollars) %>% 
  dplyr::rename(`Economic sector` = Title)

# Minor revisions made to shorten labels directly in CSV for plotting
write_csv(data.frame(dollars_by_sector), file = file.path(data_path, "dollars_by_sector.csv"))

# Sumamrize total approved loan dollars by 2 levels of NAICS hierarchy
dollars_by_prof_sector <- loan_data_raw %>% 
  dplyr::filter(Title == "Professional, Scientific, and Technical Services") %>% 
  dplyr::group_by(Title_Subgroup1, Title_Subgroup2) %>% 
  dplyr::summarize(Dollars = sum(CurrentApprovalAmount))

