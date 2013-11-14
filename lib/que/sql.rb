module Que
  module SQL
    class << self
      def create_sql
        <<-SQL
CREATE TABLE que_jobs
(
  priority integer     NOT NULL DEFAULT 1,
  run_at   timestamptz NOT NULL DEFAULT now(),
  job_id   bigserial   NOT NULL,
  type     text        NOT NULL,
  args     json        NOT NULL DEFAULT '[]'::json,

  CONSTRAINT jobs_pkey PRIMARY KEY (priority, run_at, job_id)
);
        SQL
      end

      def drop_sql
        "DROP TABLE que_jobs;"
      end

      def clear_sql
        "DELETE FROM que_jobs;"
      end

      def lock_job_sql
        <<-SQL
WITH RECURSIVE cte AS (
  SELECT (job).*, pg_try_advisory_lock((job).job_id) AS locked
  FROM (
    SELECT job
    FROM que_jobs AS job
    WHERE run_at <= now()
    ORDER BY priority, run_at, job_id
    LIMIT 1
  ) AS t1
  UNION ALL (
  SELECT (job).*, pg_try_advisory_lock((job).job_id) AS locked
  FROM (
    SELECT (
     SELECT job
      FROM que_jobs AS job
      WHERE run_at <= now() AND (priority, run_at, job_id) > (cte.priority, cte.run_at, cte.job_id)
      ORDER BY priority, run_at, job_id
      LIMIT 1
    ) AS job
    FROM cte
    WHERE NOT cte.locked
    LIMIT 1
  ) AS t1)
)
SELECT *
FROM cte
WHERE locked
LIMIT 1
        SQL
      end

      # An alternate scheme using LATERAL, which will arrive in Postgres 9.3.
      # Basically the same, but benchmark to see if it's faster/just as reliable.

      # with recursive
      #  t as (select *, pg_try_advisory_lock(s.job_id) as locked
      #          from (select * from jobs j
      #                 where run_at >= now()
      #                 order by priority, run_at, job_id limit 1) s
      #        union all
      #        select j.*, pg_try_advisory_lock(j.job_id)
      #          from (select * from t where not locked) t,
      #               lateral (select * from jobs
      #                         where run_at >= now()
      #                           and (priority,run_at,job_id) > (t.priority,t.run_at,t.job_id)
      #                         order by priority, run_at, job_id limit 1) j
      # select * from t where locked;
    end
  end
end
