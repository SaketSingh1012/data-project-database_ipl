-- Imported matches.csv file into matches table
CREATE TABLE matches ( id serial PRIMARY KEY, season integer, city text, date date, team1 text, team2 text, toss_winner text, toss_decision text, result text, dl_applied boolean, winner text, win_by_runs integer, win_by_wickets integer, player_of_match text, venue text, umpire1 text, umpire2 text, umpire3 text );
copy matches FROM '/var/lib/postgresql/matches.csv' DELIMITER ',' CSV HEADER;

-- Imported deliveries.csv file into deliveries table
CREATE TABLE deliveries ( match_id INT, inning INT, batting_team text, bowling_team text, over DECIMAL(5,2), ball INT, batsman text, non_striker text, bowler text, is_super_over int, wide_runs INT, bye_runs INT, legbye_runs INT, noball_runs INT, penalty_runs INT, batsman_runs INT, extra_runs INT, total_runs INT, player_dismissed text, dismissal_kind text, fielder text );
copy deliveries FROM '/var/lib/postgresql/deliveries.csv' DELIMITER ',' CSV HEADER;

-- 1.Number of matches per year
SELECT season, COUNT(*) AS matches_count
FROM matches
GROUP BY season
ORDER BY season;

-- 2.Matches won per team per year
SELECT season, winner, COUNT(*) as matches_won
FROM matches
GROUP BY season, winner
ORDER BY season, matches_won DESC;

-- 3.Extra runs in 2016 per team
SELECT m.season, d.bowling_team AS team, SUM(d.extra_runs) AS total_extra_runs
FROM matches AS m
INNER JOIN deliveries AS d ON m.id = d.match_id
WHERE m.season = 2016
GROUP BY m.season, d.bowling_team
ORDER BY m.season, total_extra_runs DESC;

-- 4.Top 10 economical bowlers in 2015
WITH RunsConcededByBowler AS (
    SELECT
        d.match_id,
        d.bowler,
        SUM(d.total_runs - d.legbye_runs - d.bye_runs - d.penalty_runs) AS total_runs_conceded
    FROM
        deliveries d
    JOIN
        matches m
    ON
        d.match_id = m.id
    WHERE
        m.season = 2015
    GROUP BY
        d.match_id,
        d.bowler
),
TotalDeliveriesByBowler AS (
    SELECT
        d.match_id,
        d.bowler,
        COUNT(*) AS total_deliveries
    FROM
        deliveries d
    JOIN
        matches m
    ON
        d.match_id = m.id
    WHERE
        m.season = 2015
        AND d.wide_runs = 0
        AND d.noball_runs = 0
    GROUP BY
        d.match_id,
        d.bowler
)
SELECT
    rb.bowler,
    ROUND((SUM(rb.total_runs_conceded) * 6.0) / SUM(tdb.total_deliveries), 2) AS economy
FROM
    RunsConcededByBowler rb
JOIN
    TotalDeliveriesByBowler tdb
ON
    rb.match_id = tdb.match_id
    AND rb.bowler = tdb.bowler
GROUP BY
    rb.bowler
ORDER BY
    economy
LIMIT 10;

-- 5.Toss winner match winner
SELECT team, COUNT(*) AS count
FROM (
    SELECT toss_winner AS team
    FROM matches
    WHERE toss_winner = winner
) AS subquery
GROUP BY team
ORDER BY count DESC;

-- 6.Player of the match by season
SELECT season, player_of_match
FROM (
    SELECT season, player_of_match, COUNT(*) AS match_count,
           DENSE_RANK() OVER (PARTITION BY season ORDER BY COUNT(*) DESC ) AS rn
    FROM matches
    GROUP BY season, player_of_match
) subquery
WHERE rn = 1;

-- 7.Strike of a batsman per season
WITH DhoniDeliveries AS (
    SELECT d.match_id, d.batsman, d.batsman_runs, d.wide_runs
    FROM deliveries d
    WHERE d.batsman = 'MS Dhoni'
),
DhoniRuns AS (
    SELECT dd.match_id, SUM(dd.batsman_runs) AS total_runs
    FROM DhoniDeliveries dd
    GROUP BY dd.match_id
),
DhoniBallsFaced AS (
    SELECT dd.match_id, COUNT(*) - SUM(CASE WHEN wide_runs > 0 THEN 1 ELSE 0 END) AS total_balls_faced
    FROM DhoniDeliveries dd
    GROUP BY dd.match_id
)
SELECT m.season,
       ROUND((SUM(DR.total_runs) / SUM(DBF.total_balls_faced) * 100)::numeric, 2) AS MS_Dhoni_strike_rate
FROM matches m
JOIN DhoniRuns DR ON m.id = DR.match_id
JOIN DhoniBallsFaced DBF ON m.id = DBF.match_id
GROUP BY m.season
ORDER BY m.season;

-- 8.Hisghest dismissals
WITH BowlerWickets AS (
  SELECT
    d.bowler,
    d.player_dismissed AS batsman_dismissed,
    COUNT(*) AS wickets
  FROM
    deliveries AS d
  JOIN
    matches AS m ON d.match_id = m.id
  WHERE
    m.season IS NOT NULL
    AND d.dismissal_kind != 'run out'
  GROUP BY
    d.bowler,
    d.player_dismissed
),
MaxWicketsPerBowler AS (
  SELECT
    bowler,
    batsman_dismissed,
    wickets,
    RANK() OVER (PARTITION BY bowler ORDER BY wickets DESC) AS rank
  FROM
    BowlerWickets
)
SELECT
  bowler AS "Bowler",
  batsman_dismissed AS "Batsman",
  wickets AS "Wickets"
FROM
  MaxWicketsPerBowler
WHERE
  rank = 1
ORDER BY
  wickets DESC
LIMIT 1;

-- 9.Best economy in super over
With t1 as (Select bowler,sum(total_runs-legbye_runs-bye_runs-penalty_runs) as total_runs_conceded,sum(
case 
	when wide_runs=0 and noball_runs=0 Then 1
end
) as total_fair_deliveries from deliveries where is_super_over=1 group by bowler)
Select bowler,round((total_runs_conceded*6.0)/total_fair_deliveries,2) as eco from t1 order by eco limit 1;