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
                select * from globalpermissionentry WHERE permission IN ('USE', 'ADMINISTER')
             ) AS globalpermissionentry ON cwd_membership.lower_parent_name=globalpermissionentry.group_id
             LEFT JOIN (select * from cwd_user_attributes WHERE attribute_name in ('login.lastLoginMillis')) cwd_user_attributes ON user_id= cwd_user.id
        WHERE cwd_user.active=1
       GROUP BY 1,2,3;
grant select on queries.active_users to jira_ro;
