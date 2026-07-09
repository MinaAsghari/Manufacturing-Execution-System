function verify_b3()
% VERIFY_B3  Band 3: verify Johnson vs exact (mathematical) optimum by brute force
% Works best for n <= 9 (factorial growth).

cfg.server   = "localhost";
cfg.port     = 1433;
cfg.database = "DIBRIS_BIKE";
cfg.user     = "sa";
cfg.password = "SqlServer!123";

batch_id = 1;

% ---- Connect (NO forName check) ----
conn = mssql_connect(cfg);

% خواندن داده و ساخت کویری
sql = sprintf( ...
    "SELECT id, processing_time_on_welding, processing_time_on_oven " + ...
    "FROM dbo.cutted_tubes WHERE batch_id = %d ORDER BY id;", batch_id);

tubes = mssql_query(conn, sql);   % columns: [id, weld, oven]اجرای کویری
mssql_close(conn);

ids = tubes(:,1); % اینجا ستون ها رو از هم جدا می کنیم
A   = tubes(:,2); % time of welding
B   = tubes(:,3); % time of oven
n   = numel(ids); % تعداد کل جاب ها

fprintf("Batch %d: n=%d tubes\n", batch_id, n); % تعداد تیوب ها رو نمایش میده
if n > 9
    warning("n is large for brute-force. For band 3, use a smaller instance (<=9) or we switch to MILP.");
end

% ---- Johnson ----
jIdx = johnson_order(A, B); % ترتیب بهینه را پیدا می کند
jSeq = ids(jIdx);
jMakespan = makespan_2machine(A(jIdx), B(jIdx));

fprintf("\nJohnson sequence: ");
fprintf("%d ", jSeq); % نمایش ترتیب
fprintf("\nJohnson makespan: %d\n", jMakespan); % نمایش زمان کل

% ---- Exact optimum (brute force) ----
[optIdx, optMakespan] = brute_force_opt(A, B); % تمام پریمیوتیشنهای ممکن رو بررسی می کند تا جواب واقعی را پیدا کند
optSeq = ids(optIdx);

fprintf("\nExact optimum sequence: ");
fprintf("%d ", optSeq);
fprintf("\nExact optimum makespan: %d\n", optMakespan);

% ---- Compare ----
if optMakespan == jMakespan
    fprintf("\n✅ VERIFIED (Band 3): Johnson makespan equals exact optimum.\n");
else
    fprintf("\n❌ NOT MATCHING: Johnson=%d, Opt=%d (we need to inspect data/implementation).\n", jMakespan, optMakespan);
end

end

% ================= Core scheduling =================

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

seqIdx = [front, fliplr(back)]; % اینجا ترتیب نهایی ساخته میشه
end

function Cmax = makespan_2machine(Aseq, Bseq) % محاسبه کل زمان تولید
n = numel(Aseq);
e1 = 0;
e2 = 0;
for i = 1:n
    e1 = e1 + Aseq(i); % ماشین اول جاب را انجام میده
    e2 = max(e2, e1) + Bseq(i); % ماشین دوم صبر میکنه
end
Cmax = e2; % کل زمان نهایی تولید
end

% === Exact (mathematical) solution via brute force ===

function [bestIdx, bestCmax] = brute_force_opt(A, B)
n = numel(A); % تعداد جاب ها

% perms explodes quickly; for n<=9 it's ok-ish
P = perms(1:n);  % each row is a sequence همه ترتیب های ممکن را می سازد
bestCmax = inf; % بی تهایت - infinite
bestIdx = P(1,:);

for r = 1:size(P,1) % روی همه پرمیوتیشنها لوپ می زند
    idx = P(r,:);
    C = makespan_2machine(A(idx), B(idx));
    if C < bestCmax
        bestCmax = C; % بهترین جواب انتخاب میشود
        bestIdx = idx;
    end
end
end

% ================= JDBC helpers (same idea as run_ex2) =================

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

function data = mssql_query(conn, sql)
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