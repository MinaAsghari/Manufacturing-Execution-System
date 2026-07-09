USE DIBRIS_BIKE;

SELECT * 
FROM dbo.cutted_tubes
WHERE batch_id = 2;

SELECT *
FROM dbo.johnson_schedule
WHERE batch_id = 2
ORDER BY sequence_pos;