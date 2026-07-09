CREATE DATABASE DIBRIS_BIKE;
GO

USE DIBRIS_BIKE;
GO

-- Table: cutted tubes (accumulation area)
CREATE TABLE dbo.cutted_tubes (
    id INT IDENTITY(1,1) PRIMARY KEY,
    batch_id INT NOT NULL,
    processing_time_on_welding INT NOT NULL,
    processing_time_on_oven INT NOT NULL
);

-- Table: Johnson scheduling results
CREATE TABLE dbo.johnson_schedule (
    schedule_id INT IDENTITY(1,1) PRIMARY KEY,
    batch_id INT NOT NULL,
    tube_id INT NOT NULL,
    sequence_pos INT NOT NULL,

    machine1_start INT,
    machine1_end   INT,
    machine2_start INT,
    machine2_end   INT,

    makespan INT,
    created_at DATETIME2 DEFAULT SYSUTCDATETIME(),

    CONSTRAINT FK_johnson_tube
        FOREIGN KEY (tube_id)
        REFERENCES dbo.cutted_tubes(id)
);