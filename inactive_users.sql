-- Creates a queries.inactive_users view in a Jira database, listing inactive user accounts that might be deactivated by deactivate-inactive-jira-users.groovy
--
-- Last updated: 8/Aug/21
-- See https://www.redradishtech.com/display/KB/Automatically+deactivating+inactive+Jira+users

-- @provides queries.inactive_users
create schema if not exists queries;
drop view if exists queries.inactive_users;
create view queries.inactive_users AS
WITH userlogins AS (
        SELECT DISTINCT ON (user_name) -- If LDAP is used there will be 2 directories ('LDAP' and 'Jira Internal Directory'), each with a duplicate set of cwd_user rows. The "DISTINCT ON (user_name) ... ORDER BY user_name, cwd_directory.directory_position ASC" gets us only the first cwd_user record by directory 'position', i.e. the one actually authenticated against that will have up-to-date lastLogin stats.
        user_name
        , email_address
        , cwd_user.created_date
        , timestamp with time zone 'epoch'+lastlogins.attribute_value::numeric/1000 * INTERVAL '1 second' AS lastlogin
        , timestamp with time zone 'epoch'+lastauths.attribute_value::numeric/1000 * INTERVAL '1 second' AS lastauth
        , cwd_user.directory_id
        FROM
        cwd_user
        JOIN (select * from cwd_directory WHERE directory_type='INTERNAL' and active=1) as cwd_directory ON cwd_user.directory_id = cwd_directory.id
        JOIN cwd_membership ON cwd_membership.lower_child_name=cwd_user.lower_user_name
        JOIN (
                select * from globalpermissionentry WHERE permission IN ('USE', 'ADMINISTER')
             ) AS globalpermissionentry ON cwd_membership.lower_parent_name=globalpermissionentry.group_id
             LEFT JOIN (select * from cwd_user_attributes WHERE attribute_name in ('login.lastLoginMillis')) lastlogins ON lastlogins.user_id=cwd_user.id
             LEFT JOIN (select * from cwd_user_attributes WHERE attribute_name in ('lastAuthenticated')) lastauths ON lastauths.user_id=cwd_user.id
        WHERE cwd_user.active=1 AND NOT (
		cwd_user.lower_email_address like '%@mycompany.com'
		OR email_address=''
		-- Specific exceptions can be added to the 'never-deactivate' group.
	)
	ORDER BY user_name, cwd_directory.directory_position ASC
)
, lastassigns AS (
        SELECT DISTINCT
        newvalue AS user_name
        , max(created) AS lastassign
        FROM changegroup cg
        JOIN changeitem ci ON cg.id = ci.groupid
        WHERE field='assignee' group by 1
)
, lastwatch AS (
	select cwd_user.user_name
	, max(userassociation.created) AS lastwatch FROM app_user LEFT JOIN userassociation ON userassociation.source_name=app_user.user_key JOIN cwd_user USING (lower_user_name) WHERE association_type='WatchIssue' group by user_name
)
, neverdeactivate AS (
	select cwd_user.user_name from cwd_user JOIN cwd_membership ON cwd_user.id=cwd_membership.child_id JOIN cwd_group ON cwd_membership.parent_id=cwd_group.id WHERE cwd_group.group_name='never-deactivate'
)
SELECT distinct
	user_name
	, email_address
	, to_char(created_date, 'YYYY-MM-DD') AS created
	, to_char(lastlogin, 'YYYY-MM-DD') AS lastlogin
	, to_char(lastauth, 'YYYY-MM-DD') AS lastauth
	, to_char(lastassign, 'YYYY-MM-DD') AS lastassign
	, to_char(lastwatch, 'YYYY-MM-DD') AS lastwatch
	, (select count(*) from jiraissue where assignee=userlogins.user_name) AS assigneecount
FROM userlogins LEFT JOIN lastassigns USING (user_name)
LEFT JOIN lastwatch USING (user_name)
 WHERE
	(created_date < now() - '6 months'::interval)
	AND ((lastlogin < now() - '6 months'::interval) OR lastlogin is null) 
	AND ((lastauth < now() - '6 months'::interval) OR lastauth is null) 
	AND ((lastassign < now() - '6 months'::interval) OR lastassign is null)
	AND ((lastwatch < now() - '6 months'::interval) OR lastwatch is null)
	AND NOT EXISTS (select * from neverdeactivate where user_name=userlogins.user_name)
ORDER BY lastlogin desc nulls last ;
GRANT select on queries.inactive_users to jira_ro;
