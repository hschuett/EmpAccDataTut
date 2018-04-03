# Imports -----------------------------------------------------------------
library(tidyverse)


# Load data ---------------------------------------------------------------
# data souce:
# https://catalog.data.gov/dataset/nutrition-physical-activity-and-obesity-behavioral-risk-factor-surveillance-system
# https://www.cdc.gov/brfss/data_documentation/index.htm
# documentation for the sampling:
#     https://www.cdc.gov/brfss/

survey<- read.csv("data/Nutrition_Physical_Activity_and_Obesity.csv")
# this dataset has a weird structure.
# Let's look at it a while
# Ideally, if you get a dataset like this, you also get a description
# of what each variable codes
str(survey, width=80)
# it also seems some of the variables are superfluous?
unique(survey$Class)
unique(survey$Topic)
table(survey$Class, survey$Topic)
# hundred percet congruence
# delete topic, classID, topicid
table(survey$YearEnd, survey$YearStart)
# delete yearend, rename yearstart to year

cor(survey$Data_Value, survey$Data_Value_Alt, use="complete.obs")
colSums(is.na(survey[, c("Data_Value", "Data_Value_Alt")]))

unique(survey$Data_Value_Footnote)
unique(survey$Data_Value_Footnote_Symbol)

csurvey <- survey %>%
  select(-Topic, -TopicID, -ClassID, -YearEnd, -LocationDesc, -LocationID,
         -Data_Value_Type, -Data_Value_Unit, -Datasource, -Data_Value_Alt,
         -Data_Value_Footnote_Symbol, -DataValueTypeID,
         -Age.years., -Education, -Gender, -Income, -Race.Ethnicity) %>%
  rename(Year = YearStart)


total_respondants_answers <- csurvey %>%
  filter(Total == "Total")

# Visualization -----------------------------------------------------------

ggplot(data=total_respondants_answers) +
  facet_wrap(~Question, ncol=2) +
  geom_point(aes(x=LocationAbbr, y=Data_Value), alpha=0.3)

# you could see from this picture, how you could turn this into a dataset.
# You could turn this into nine variables
# BUT, be careful! These are sample percent! They have a distribution.

questions <- csurvey %>%
  select(Question, QuestionID) %>%
  distinct()

new_data <- total_respondants_answers %>%
  select(Year, LocationAbbr, Data_Value, QuestionID) %>%
  spread(key=QuestionID, value=Data_Value)  # makes long data wider

ggplot(data=new_data) +
  geom_point(aes(x=LocationAbbr, y=Q036, color=Year))

ggplot(data=new_data) +
  geom_point(aes(x=LocationAbbr, y=Q036, color=Year)) +
  geom_line(aes(x=LocationAbbr, y=Q036, color=Year))

# takeaways:
# Ist there a general upward trend? Or is this sampling variation???
# telephone survey (50.000 calls???)


# Now lets play with the sub samples....


cor(new_data %>% select(starts_with("Q")),
    use="complete.obs") %>% round(2)
