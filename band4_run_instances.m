function band4_run_instances()
% BAND4_RUN_INSTANCES  Generate multiple instances (batches), run Johnson,
% store schedules to SQL, and verify vs exact optimum for small n.

cfg.server   = "localhost";
cfg.port     = 1433;
cfg.database = "DIBRIS_BIKE";
cfg.user     = "sa";
cfg.password = "SqlServer!123";

% ---- Band 4 settings ----
firstBatch = 2;
numBatches = 5;    % چند instance بسازیم
nJobs      = 6;    % برای brute-force بهتره 6 یا 7
tMin       = 1;    % حداقل زمان پردازش
tMax       = 10;   % حداکثر زمان پردازش
rngSeed    = 2026; % برای تکرارپذیری گزارش

rng(rngSeed);

conn = mssql_connect(cfg);

results = zeros(numBatches, 6); % یک ماتریس برای ذخیره نتایح میده
% columns: batch_id, n, johnson_ms, opt_ms, gap, verified(0/1)

for b = 1:numBatches
    batch_id = firstBatch + (b-1);

    % 1) delete old data for this batch (clean)
    mssql_exec(conn, sprintf("DELETE FROM dbo.johnson_schedule WHERE batch_id=%d;", batch_id));
    mssql_exec(conn, sprintf("DELETE FROM dbo.cutted_tubes WHERE batch_id=%d;", batch_id));

    % 2) generate random instance
    A = randi([tMin tMax], nJobs, 1); % welding time
    B = randi([tMin tMax], nJobs, 1); % oven time

    % 3) insert tubes in database
    tubeIds = zeros(nJobs,1);
    for i = 1:nJobs
        ins = sprintf( ...
            "INSERT INTO dbo.cutted_tubes (batch_id, processing_time_on_welding, processing_time_on_oven) " + ...
            "VALUES (%d, %d, %d);" , batch_id, A(i), B(i));
        mssql_exec(conn, ins);
    end

    % read back ids (so we know tube_id values)ـ ساخت کوئری ـ
    q = sprintf("SELECT id, processing_time_on_welding, processing_time_on_oven FROM dbo.cutted_tubes WHERE batch_id=%d ORDER BY id;", batch_id);
    tubes = mssql_query(conn, q); % خواندن اطلاعات
    tubeIds = tubes(:,1);
    A = tubes(:,2);
    B = tubes(:,3);

    % 4) Johnson --- پیدا کردن بهترین چیدمان تسک
    jIdx = johnson_order(A, B);
    jSeqIds = tubeIds(jIdx); % ترتیب واقعی تیوبها
    jMs = makespan_2machine(A(jIdx), B(jIdx)); % محاسبه میک اسپن جانسون

    % 5) timing and store schedule شروع و پایان اسکجولها ـ
    [s1,e1,s2,e2] = two_machine_timing(A(jIdx), B(jIdx));
    store_schedule(conn, batch_id, jSeqIds, s1, e1, s2, e2, jMs);

    % 6) exact optimum (brute-force) for small n
    [~, optMs] = brute_force_opt(A, B);
    verified = (optMs == jMs);
    gap = jMs - optMs; % گپ باید صفر باشد

    results(b,:) = [batch_id, nJobs, jMs, optMs, gap, verified]; % نتایج بچ ها ذخیره می شود

    fprintf("Batch %d | n=%d | Johnson=%d | Opt=%d | gap=%d | verified=%d\n", ...
        batch_id, nJobs, jMs, optMs, gap, verified);
end

mssql_close(conn);

disp(" "); % عنوان تیبل چاپ می شه
disp("Summary [batch_id  n  johnson  optimum  gap  verified]");
disp(results);

end

% === SQL helpers ===

function conn = mssql_connect(cfg)
jdbcUrl = sprintf( ...
    "jdbc:sqlserver://%s:%d;databaseName=%s;encrypt=false;trustServerCertificate=true;", ...
    cfg.server, cfg.port, cfg.database);

props = java.util.Properties();
props.setProperty("user", cfg.user);
props.setProperty("password", cfg.password);

conn.jconn = java.sql.DriverManager.getConnection(jdbcUrl, props);
end

function mssql_close(conn)
conn.jconn.close();
end

function data = mssql_query(conn, sql) % برای اجرای سلکت
stmt = conn.jconn.createStatement();
rs = stmt.executeQuery(sql);
md = rs.getMetaData();
ncol = md.getColumnCount();

rows = {};
while rs.next()
    r = zeros(1, ncol);
    for c = 1:ncol
        r(c) = rs.getLong(c);
    end
    rows{end+1,1} = r; %#ok<AGROW>
end
rs.close(); stmt.close();

if isempty(rows)
    data = zeros(0, ncol);
else
    data = vertcat(rows{:});
end
end

function mssql_exec(conn, sql)
stmt = conn.jconn.createStatement();
stmt.execute(sql);
stmt.close();
end

% === Johnson + timing ===

function seqIdx = johnson_order(A, B)
n = numel(A);
remaining = true(1,n);
front = [];
back  = [];

for k = 1:n
    idx = find(remaining);
    [minA, ia] = min(A(idx));
    [minB, ib] = min(B(idx));

    if minA <= minB
        j = idx(ia);
        front(end+1) = j; %#ok<AGROW>
    else
        j = idx(ib);
        back(end+1) = j; %#ok<AGROW>
    end
    remaining(j) = false;
end
seqIdx = [front, fliplr(back)];
end

function [s1, e1, s2, e2] = two_machine_timing(Aseq, Bseq)
n = numel(Aseq);
s1 = zeros(n,1); e1 = zeros(n,1);
s2 = zeros(n,1); e2 = zeros(n,1);

for i = 1:n
    if i == 1
        s1(i) = 0;
    else
        s1(i) = e1(i-1);
    end
    e1(i) = s1(i) + Aseq(i);

    if i == 1
        s2(i) = e1(i);
    else
        s2(i) = max(e1(i), e2(i-1));
    end
    e2(i) = s2(i) + Bseq(i);
end
end

function Cmax = makespan_2machine(Aseq, Bseq)
n = numel(Aseq);
e1 = 0; e2 = 0;
for i = 1:n
    e1 = e1 + Aseq(i);
    e2 = max(e2, e1) + Bseq(i);
end
Cmax = e2;
end

% ================= Exact optimum (brute force) =================

function [bestIdx, bestCmax] = brute_force_opt(A, B)
n = numel(A); % تعداد جاب ها را محاسبه می کند
P = perms(1:n); % تمام پرمیوتیشن ها رو تولید می کند
bestCmax = inf; 
bestIdx = P(1,:); % اولین پرمیوتیشن رو به عنوان جواب اولیه می گذارد
for r = 1:size(P,1)
    idx = P(r,:);
    C = makespan_2machine(A(idx), B(idx));
    if C < bestCmax
        bestCmax = C;
        bestIdx = idx;
    end % اگر ما سه جاب داشته باشیم ۶ بار حلقه اجرا میشه
end
end

function store_schedule(conn, batch_id, tubeIds, s1, e1, s2, e2, makespan)
del = sprintf("DELETE FROM dbo.johnson_schedule WHERE batch_id=%d;", batch_id);
mssql_exec(conn, del);

n = numel(tubeIds);
for pos = 1:n
    ins = sprintf( ...
        "INSERT INTO dbo.johnson_schedule " + ...
        "(batch_id, tube_id, sequence_pos, machine1_start, machine1_end, machine2_start, machine2_end, makespan) " + ...
        "VALUES (%d, %d, %d, %d, %d, %d, %d, %d);" , ...
        batch_id, tubeIds(pos), pos, s1(pos), e1(pos), s2(pos), e2(pos), makespan);
    mssql_exec(conn, ins);
end
end