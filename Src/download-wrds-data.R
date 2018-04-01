# (C) Harm Schuett 2018, schuett@bwl.lmu.de, see LICENSE file for details
# This file connects to the wrs

# Imports ---------------------------------------------------------------------------
# Loading library and preliminaries
library(RPostgres)
library(dplyr)
library(lubridate)

# IMPORTANT! Set the working directory
setwd("c:/Users/schuett/Dropbox/GitRepos/EmpAccDataTut/")

# Sample data range
begin_date <- "1980-01-01"
end_date   <- "2011-01-01"

# Establishing wrds connection
# WRDS does not allow your passwords to be saved anywhere in clear form, so
# we prompt for it:
user <- readline("Enter your username: ")
pass <- readline("Enter your password: ")
wrds <- dbConnect(Postgres(),
                  host='wrds-pgdata.wharton.upenn.edu',
                  port=9737,
                  user=user,
                  password=pass,
                  sslmode='require',
                  dbname='wrds')
wrds  # checking if connection exists



# Downloading Compustat Data --------------------------------------------------------
# We will only download and merge the raw data here. Everything else should be done
# somewhere as part of a separate script.
# Note: Postgres needs '' for strings funny enough

res1 <- dbSendQuery(wrds,
                    paste("SELECT sich, a.gvkey, a.indfmt,
                                  tic, datadate, fyear, a.conm, fyr, at, che, oiadp, act,
                                  lct, dlc, txp, dp,
                                  b.loc, b.sic, b.spcindcd, b.ipodate, b.stko
                           FROM COMP.FUNDA as a
                              LEFT JOIN comp.company as b
                                ON a.gvkey = b.gvkey
                           WHERE consol='C'
                             and indfmt='INDL'
                             and datafmt='STD'
                             and popsrc='D'
                             and datadate between '", begin_date, "' and '", end_date,"'
                           ORDER BY a.gvkey, datadate"))
df_funda <- dbFetch(res1, n=-1)
dbClearResult(res1)
# The crsp and compustat databases have different identifiers.
# In Compustat, every firm has a unique key called "gvkey". In
# CRSP, every firm as a unique "permno" key. You cannot match simply
# by name. Names change and might be different from file to file
# (e.g., "Apple Inc" and "APPLE INCORPORATED). Well you can, fix these things,
# but it is noisy. You also cannot match by stock ticker, because stock tickers
# are not unique. They get reused over time.
# You can do all this by yourself, but WRDS provides a convenient linking table.
# We are going to use that
res2 <- dbSendQuery(wrds,
                    paste("SELECT *
                           FROM crsp.ccmxpf_linktable
                           WHERE usedflag in (0, 1)
                             and linktype in ('LU', 'LC')"))
df_ccm_link <- dbFetch(res2, n=-1) %>%
  mutate(linkenddt = if_else(is.na(linkenddt) == T, date("2030-06-30"), linkenddt))
dbClearResult(res2)

df_funda2 <- df_funda %>%
  distinct() %>%
  left_join(df_ccm_link, by="gvkey") %>%
  filter(is.na(linkdt) == T | (linkdt <= datadate & datadate <= linkenddt)) %>%
  group_by(gvkey, datadate) %>%
  # taking only primary link if multiple permnos per gvkey
  mutate(countkey2 = n()) %>%
  ungroup() %>%
  filter(countkey2 == 1 | (countkey2 > 1 & liid == "01")) %>%
  select(-countkey2)


saveRDS(df_funda2, "Data/raw_compu.rds")
rm(df_funda, df_funda2, df_ccm_link)
rm(res1, res2)



# Downloading CRSP Data -------------------------------------------------------------
# Same as with Compustat data, although the crsp data is a bit more scattered.
# Need to grab data from multiple tables and merge it. We need:
# msf: monthly stock return file
# mseall: monthly stock events (like delisting data)
# msi: monthly index file
# ermport1: decile portfolio returns file
# ff: fama french factors

# If you want to figure out the names of the tables in the crsp schema:
# res <- dbSendQuery(wrds, "select distinct table_name
#                    from information_schema.columns
#                    where table_schema='crsp'
#                    order by table_name")
# data <- dbFetch(res, n=-1)
# dbClearResult(res)
# data

# This is a more complicated sql query. I am only doing it like this
# because the joins take a lot of memory and I'd rather do that on the wrds
# cloud instead of a laptop etc.
ff_start <- substr(begin_date, 1, 4)
ff_end <- substr(end_date, 1, 4)
res3 <- dbSendQuery(wrds,
                    paste0("SELECT S.*, D.decret, E.vwretd, E.ewretd,
                                   FF.smb, FF.hml, FF.mktrf, FF.rf
                            FROM (SELECT a.permno, a.date, a.prc, a.ret, a.vol, a.shrout,
                                         b.ticker, b.ncusip, b.comnam,
                                         b.exchcd, b.shrcd, b.dlret, b.dlstcd, b.siccd,
                                         to_char(a.date, 'YYYY-MM') as year_month
                                  FROM crsp.msf as a
                                    LEFT JOIN crsp.mseall as b
                                      ON    a.permno = b.permno
                                        and a.date = b.date
                                  WHERE a.date between '", begin_date, "' and '", end_date,"') as S
                            LEFT JOIN (SELECT decret, permno,
                                              to_char(date, 'YYYY-MM') as d_ym
                                      FROM crsp.ermport1
                                      WHERE date between '", begin_date, "' and '", end_date,"') as D
                              ON s.permno = D.permno
                                  and S.year_month = D.d_ym
                            LEFT JOIN (SELECT vwretd, ewretd,
                                              to_char(date, 'YYYY-MM') as e_ym
                                      FROM crsp.msi
                                      WHERE date between '", begin_date, "' and '", end_date,"') as E
                              ON S.year_month = E.e_ym
                            LEFT JOIN (SELECT smb, hml, mktrf, rf,
                                              year::text || '-' || LPAD(month::text, 2, '0') as f_ym
                                      FROM ff.factors_monthly
                                      WHERE year between '", ff_start, "' and '", ff_end, "') as FF
                              ON S.year_month = FF.f_ym
                           "))
df_stock <- dbFetch(res3, n=-1)
dbClearResult(res3)

# Orderly clean up
dbDisconnect(wrds)

# Taking the downloaded data and compute the raw data for all tests.
df_stock2 <- df_stock %>%
  distinct() %>%
  filter(is.na(date) == F) %>%
  # for whatever reason, shrcd and exchcd are extremely spotty. We need to
  # fill that bevore we can filter
  arrange(permno, date) %>%
  group_by(permno) %>%
  mutate(lagshrcd = lag(shrcd),
         leadshrcd = lead(shrcd),
         lagexchcd = lag(exchcd),
         leadexchcd = lead(exchcd)) %>%
  ungroup() %>%
  mutate(exchcd = case_when(is.na(exchcd) == T & is.na(lagexchcd) == F ~ lagexchcd,
                            is.na(exchcd) == T & is.na(leadexchcd) == F ~ leadexchcd,
                            TRUE ~ exchcd),
         shrcd = case_when(is.na(shrcd) == T & is.na(lagshrcd) == F ~ lagshrcd,
                            is.na(shrcd) == T & is.na(leadshrcd) == F ~ leadshrcd,
                            TRUE ~ shrcd)) %>%
  # Share Code (shrcd) restrict to ordinary shares
  # Exchange Code (exchcd) restrict to NYSE, NASDAQ, AMEX
  filter(shrcd %in% c(10, 11) & exchcd %in% c(1,2,3)) %>%
  select(-lagshrcd, -leadshrcd, -lagexchcd, -leadexchcd) %>%
  # Incorporate delisting returns
  mutate(MktValEq = abs(prc) * shrout / 1000,
         # In old sas, missing values where coded like this: -66, -77, -88 etc;
         # Don't think that is the case anymore.
         ret   = if_else(ret < -55, NA_real_, ret),
         dlret = if_else((dlstcd == 500 | (dlstcd <= 584 & dlstcd >=520)) & is.na(dlret) == T, -1, dlret)) %>%
  mutate(dlret = if_else(is.na(dlret) == T, 0, dlret)) %>%
  mutate(ret = if_else(is.na(ret) == T & is.na(dlstcd) == F, dlret, ret)) %>%
  select(-dlret)

saveRDS(df_stock2, "Data/raw_crsp.rds")


# test <- df_stock2 %>%
#   select(permno, date, ret, dlret, dlstcd) %>%
#   head(100)
