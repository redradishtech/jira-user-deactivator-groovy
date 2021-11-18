-- Just for fun, since we have an inactive_users.sql, here's a query showing 'active' users counting towards your Jira license count.
create schema if not exists queries;
drop view if exists queries.active_users;
create view queries.active_users AS
SELECT DISTINCT
        user_name
        , email_address
       , display_name
       , max(cwd_user.created_date) AS created_date
        FROM
        cwd_user
        JOIN (select * from cwd_directory WHERE active=1) as cwd_directory ON cwd_user.directory_id = cwd_directory.id
        JOIN cwd_membership ON cwd_membership.lower_child_name=cwd_user.lower_user_name
        JOIN (
                select * from licenserolesgroup WHERE license_role_name IN ('jira-software')
             ) AS licenserolesgroup ON cwd_membership.lower_parent_name=licenserolesgroup.group_id
             LEFT JOIN (select * from cwd_user_attributes WHERE attribute_name in ('login.lastLoginMillis')) cwd_user_attributes ON user_id= cwd_user.id
        WHERE cwd_user.active=1
       GROUP BY 1,2,3;
grant select on queries.active_users to jira_ro;



jira=> select * from licenserolesgroup;
┌───────┬───────────────────┬────────────────────────┬───────────────┐
│  id   │ license_role_name │        group_id        │ primary_group │
├───────┼───────────────────┼────────────────────────┼───────────────┤
│ 10000 │ jira-core         │ jira-administrators    │ N             │
│ 10001 │ jira-core         │ jira-users             │ Y             │
│ 10002 │ jira-software     │ jira-administrators    │ N             │
│ 10003 │ jira-software     │ jira-users             │ Y             │
│ 10100 │ jira-software     │ dlp-contractors        │ N             │
│ 10200 │ jira-servicedesk  │ jira-servicedesk-users │ Y             │
│ 10300 │ jira-software     │ c2c-developers         │ N             │
└───────┴───────────────────┴────────────────────────┴───────────────┘
(7 rows)

