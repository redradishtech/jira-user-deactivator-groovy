-- Creates a queries.inactive_users view in a Jira database, listing inactive user accounts that might be deactivated by deactivate-inactive-jira-users.groovy
--
-- See https://www.redradishtech.com/display/KB/Automatically+deactivating+inactive+Jira+users

create schema if not exists queries;
drop view if exists queries.inactive_users;
create view queries.inactive_users AS
WITH userlogins AS (
        SELECT DISTINCT
        user_name
        , email_address
        , cwd_user.created_date
        , timestamp with time zone 'epoch'+attribute_value::numeric/1000 * INTERVAL '1 second' AS lastlogin
        , cwd_user.directory_id
        FROM
        cwd_user
        JOIN (select * from cwd_directory WHERE directory_type='INTERNAL' and active=1) as cwd_directory ON cwd_user.directory_id = cwd_directory.id
        JOIN cwd_membership ON cwd_membership.lower_child_name=cwd_user.lower_user_name
        JOIN (
                select * from globalpermissionentry WHERE permission IN ('USE', 'ADMINISTER')
             ) AS globalpermissionentry ON cwd_membership.lower_parent_name=globalpermissionentry.group_id
             LEFT JOIN (select * from cwd_user_attributes WHERE attribute_name in ('login.lastLoginMillis')) cwd_user_attributes ON user_id=cwd_user.id
        WHERE cwd_user.active=1 AND
		 (cwd_user.lower_email_address not like '%@mycompany.com' OR email_address='') -- Don't deactivate anyone @mycompany.com, for example
)
, lastassigns AS (
        SELECT DISTINCT
        newvalue AS user_name
        , max(created) AS lastassign
        FROM changegroup cg
        JOIN changeitem ci ON cg.id = ci.groupid
        WHERE field='assignee' group by 1
)
SELECT distinct
        user_name
        , email_address
        , to_char(created_date, 'YYYY-MM-DD') AS created
        , to_char(lastlogin, 'YYYY-MM-DD') AS lastlogin
        , to_char(lastassign, 'YYYY-MM-DD') AS lastassign
        , (select count(*) from jiraissue where assignee=userlogins.user_name) AS assigneecount
FROM userlogins LEFT JOIN lastassigns USING (user_name)
 WHERE
        (created_date < now() - '6 months'::interval) AND
        ((lastlogin < now() - '6 months'::interval) OR lastlogin is null) AND
        ((lastassign < now() - '6 months'::interval) OR lastassign is null)
ORDER BY lastlogin desc nulls last ;
GRANT select on queries.inactive_users to jira_ro;
