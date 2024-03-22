-------------------------------------------------------------------------------------------------
--# Join all 3 together into 1 giant master table:
-------------------------------------------------------------------------------------------------
DROP TABLE master_table
SELECT DISTINCT con.*,lis.listing_neighborhood,lis.room_type,lis.total_reviews,
                users.[id_user_anon],
				USERS.[country],
				USERS.[words_in_user_profile],
				DATEDIFF(DAY,con.[ds_checkin_first],con.[ds_checkout_first]) as length_of_stay_days,
CAST(REPLACE(total_reviews,'-',' ')AS INT ) AS totalreviews,
CAST(CASE WHEN con.[ts_reply_at_first] IS NULL THEN '0' ELSE '1' END AS int)  AS replied,
CAST(CASE WHEN con.[ts_accepted_at_first] IS NULL THEN '0' ELSE '1' END AS int) AS accepted	,
CAST(CASE WHEN con.[ts_booking_at] IS NULL THEN '0' ELSE '1' END AS int) AS booked,
CASE WHEN lis.listing_neighborhood ='-unknown-' THEN '-unknown-' ELSE 'known' END  AS listingneighborhood,
CASE WHEN users.id_user_anon= con.id_host_anon THEN 'host' WHEN users.id_user_anon= con.[id_guest_anon] THEN 'guest' END  AS id_user,
CASE WHEN words_in_user_profile <=3 THEN '3 words or less' ELSE 'More than 3 words' END  AS profile_words
INTO master_table
	FROM [dbo].[users]  join contacts con 
		on users.id_user_anon= con.id_host_anon	
		or users.id_user_anon= con.[id_guest_anon]
		join [dbo].[listings] lis 
		on lis.[id_listing_anon]= con.[id_listing_anon] 
---------------------------------------------------------------------------------------------------------
--# List of flattened contacts with additional explanatory 0/1 variables for further manipulation:
---------------------------------------------------------------------------------------------------------
		SELECT id_user,
	       contact_channel_first, 
           guest_user_stage_first, 
           m_guests, m_interactions, 
           m_first_message_length_in_characters, 
           length_of_stay_days, 
           room_type,
           total_reviews,
           listingneighborhood,
           profile_words,
           replied, 
           accepted, 
           booked
		   FROM master_table
--------------------------------
--Key Metrics
--------------------------------
--Reply Rate (%): Replies / Interactions
--Booking Rate (%): Bookings / Interactions (based on initial interaction date)
--Acceptance Rate (%):  Accepted Bookings/  Interactions
--Abandonment Rate (%):  Bookings not finalized, but were accepted - (Acceptance Rate-Booking Rate)
---------------------------------------------------------------------
--Neighborhood location (known vs. unknown)
---------------------------------------------------------------------
SELECT listingneighborhood,
       sum(replied) AS replied,
       sum(accepted) accepts,
       sum(booked)  bookings,
       CAST(sum(replied)*1.0/COUNT(*)*100 AS INT)  reply_rate,
       CAST(sum(accepted)*1.0/COUNT(*)*100 AS INT)  accept_rate ,
       CAST(sum(booked)*1.0/COUNT(*)*100 AS INT)  booking_rate
		FROM master_table
		GROUP BY listingneighborhood


---------------------------------------------------------------------
--Accomodation type
---------------------------------------------------------------------
SELECT ROOM_TYPE,
       CAST(sum(replied)*1.0/COUNT(*)*100 AS INT)  reply_rate,
       CAST(sum(accepted)*1.0/COUNT(*)*100 AS INT)  accept_rate ,
       CAST(sum(booked)*1.0/COUNT(*)*100 AS INT)  booking_rate,
	   CAST(AVG(m_guests)AS INT) AS avg_m_guests
		FROM master_table
		GROUP BY ROOM_TYPE 
-----------------------------------------------------------------------
--Length of stay
-----------------------------------------------------------------------
WITH CTE AS 
(
SELECT *,
 CASE WHEN DATEDIFF(DAY,[ds_checkin_first],[ds_checkout_first])<= '7' THEN 'less than week/week'
            WHEN DATEDIFF(DAY,[ds_checkin_first],[ds_checkout_first])<= '92' THEN 'week-3 month ' 
            WHEN  DATEDIFF(DAY,[ds_checkin_first],[ds_checkout_first])<='184'  THEN '3-6 months' 
			WHEN  DATEDIFF(DAY,[ds_checkin_first],[ds_checkout_first])<='276'  THEN '6-9 months'
			ELSE 'ONE YEAR'END  AS Length_of_stay
FROM master_table )
SELECT Length_of_stay,
       contact_channel_first,
       CAST(COUNT(Length_of_stay)* 1.0/SUM(COUNT(Length_of_stay)) OVER (PARTITION BY Length_of_stay)*100 AS int),
	   CAST(sum(replied)*1.0/COUNT(*)*100 AS INT)  reply_rate,
       CAST(sum(accepted)*1.0/COUNT(*)*100 AS INT)  accept_rate ,
       CAST(sum(booked)*1.0/COUNT(*)*100 AS INT)  booking_rate,
	   CAST(SUM (COUNT(*)) OVER (PARTITION BY Length_of_stay)*1.0/SUM (COUNT(*)) OVER () *100 AS INT) AS demand_rate,
	   SUM (COUNT(*)) OVER (PARTITION BY Length_of_stay)
FROM CTE 
GROUP BY Length_of_stay,contact_channel_first
ORDER BY Length_of_stay

----------------------------------------------------------------------------------------------------------
--“Completeness” of guest and host profiles (# words)
----------------------------------------------------------------------------------------------------------
SELECT profile_words,
       id_user,
       COUNT(*),
	   COUNT(*)*1.0 / SUM(COUNT(*)) OVER (PARTITION BY id_user)*100,
       CAST(sum(replied)*1.0/COUNT(*)*100 AS INT)  reply_rate,
       CAST(sum(accepted)*1.0/COUNT(*)*100 AS INT)  accept_rate ,
       CAST(sum(booked)*1.0/COUNT(*)*100 AS INT)  booking_rate
FROM master_table 
GROUP BY profile_words,id_user
ORDER BY id_user

---------------------------------------------------------------------------------------------------
--The effect of the amount of total reviews on the order rate
--I decided to divide the amount of responses in jumps of 25 percent of 
--the total amount of the number of responses.
----------------------------------------------------------------------------------------------------
WITH CTE  AS 
(
SELECT *,
       CASE WHEN totalreviews=0 THEN '0'
            WHEN totalreviews<=4 THEN '0-4'
			WHEN totalreviews<= 18 THEN '5-18'
			WHEN totalreviews>= 18 THEN '18+' END  AS amount_totalreviews
FROM master_table 
)
SELECT  amount_totalreviews,
       CAST(sum(replied)*1.0/COUNT(*)*100 AS INT)  reply_rate,
       CAST(sum(accepted)*1.0/COUNT(*)*100 AS INT)  accept_rate ,
       CAST(sum(booked)*1.0/COUNT(*)*100 AS INT)  booking_rate
FROM CTE
GROUP BY amount_totalreviews


