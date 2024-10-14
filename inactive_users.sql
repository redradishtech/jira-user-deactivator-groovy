-- Creates a queries.inactive_users view in a Jira database, listing inactive user accounts that might be deactivated by deactivate-inactive-jira-users.groovy
--
-- Last updated: 14/Oct/24
-- See https://www.redradishtech.com/display/KB/Automatically+deactivating+inactive+Jira+users

-- @provides queries.inactive_users_all
drop view if exists queries.inactive_users_all cascade;
create schema if not exists queries;
create view queries.inactive_users_all AS
WITH userlogins AS (
        SELECT DISTINCT ON (user_name) -- If LDAP is used there will be 2 directories ('LDAP' and 'Jira Internal Directory'), each with a duplicate set of cwd_user rows. The "DISTINCT ON (user_name) ... ORDER BY user_name, cwd_directory.directory_position ASC" gets us only the first cwd_user record by directory 'position', i.e. the one actually authenticated against that will have up-to-date lastLogin stats.
		cwd_user.directory_id
        , user_name
        , email_address
        , cwd_user.created_date
        , timestamp with time zone 'epoch'+lastlogins.attribute_value::numeric/1000 * INTERVAL '1 second' AS lastlogin
        , timestamp with time zone 'epoch'+lastauths.attribute_value::numeric/1000 * INTERVAL '1 second' AS lastauth   -- REST queries count as authentications, not logins
        FROM
        cwd_user
        JOIN (select * from cwd_directory WHERE active=1) as cwd_directory ON cwd_user.directory_id = cwd_directory.id
        JOIN cwd_membership ON (cwd_membership.lower_child_name=cwd_user.lower_user_name and cwd_membership.directory_id=cwd_directory.id)
        JOIN (
                select * from globalpermissionentry WHERE permission IN ('USE', 'ADMINISTER')
             ) AS globalpermissionentry ON cwd_membership.lower_parent_name=globalpermissionentry.group_id
             LEFT JOIN LATERAL (select * from cwd_user_attributes WHERE directory_id=cwd_directory.id AND attribute_name in ('login.lastLoginMillis')) lastlogins ON lastlogins.user_id=cwd_user.id
             LEFT JOIN LATERAL (select * from cwd_user_attributes WHERE directory_id=cwd_directory.id AND attribute_name in ('lastAuthenticated')) lastauths ON lastauths.user_id=cwd_user.id
        WHERE cwd_user.active=1 
		-- Note that we cannot have any further WHERE clauses, e.g. limiting email_address to a certain pattern. Say user 'jjsmith' Internal user has email jjsmith@foo.com, and is shadowed by 'jjsmith' in LDAP, with email jjsmith@bar.com. If we limit to 'not like '%@bar.com' then only the inactive foo.com username's attributes would be found. Instead our caller must do the filtering.
		-- Specific exceptions can be added to the 'never-deactivate' group.
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
	SELECT cwd_user.user_name
		   , max(userassociation.created) AS lastwatch
	FROM app_user
	LEFT JOIN userassociation ON userassociation.source_name=app_user.user_key
	JOIN cwd_user USING (lower_user_name)
	WHERE association_type='WatchIssue'
	GROUP BY user_name )
, lastreactivate AS (
	-- Check the audit log for account reactivations.
	-- If an admin recently reactivated a dormant account, we don't want to deactivate it due to the user's inactivity
	select
		app_user.lower_user_name AS user_name
		,max(to_timestamp("ENTITY_TIMESTAMP"/1000)::date) AS lastreactivate
	 from "AO_C77861_AUDIT_ENTITY" JOIN app_user ON app_user.user_key="PRIMARY_RESOURCE_ID" where "PRIMARY_RESOURCE_TYPE"='USER' AND "CHANGE_VALUES" ~ '"from":"Inactive","to":"Active"}]$'
	group by user_name
)
, neverdeactivate AS (
	select cwd_user.user_name from cwd_user JOIN cwd_membership ON cwd_user.id=cwd_membership.child_id JOIN cwd_group ON cwd_membership.parent_id=cwd_group.id WHERE cwd_group.group_name='never-deactivate'
)
SELECT distinct
	user_name
	, directory_id
	, email_address
	, to_char(created_date, 'YYYY-MM-DD') AS created
	, to_char(lastlogin, 'YYYY-MM-DD') AS lastlogin
	, to_char(lastauth, 'YYYY-MM-DD') AS lastauth
	, to_char(lastassign, 'YYYY-MM-DD') AS lastassign
	, to_char(lastwatch, 'YYYY-MM-DD') AS lastwatch
	, to_char(lastreactivate, 'YYYY-MM-DD') AS lastreactivate
	, (select count(*) from jiraissue where assignee=userlogins.user_name) AS assigneecount
FROM userlogins
LEFT JOIN lastassigns USING (user_name)
LEFT JOIN lastreactivate USING (user_name)
LEFT JOIN lastwatch USING (user_name)
 WHERE
	(created_date < now() - '3 months'::interval)
	AND ((lastlogin < now() - '3 months'::interval) OR lastlogin is null) 
	AND ((lastauth < now() - '3 months'::interval) OR lastauth is null) 
	AND ((lastassign < now() - '3 months'::interval) OR lastassign is null)
	AND ((lastreactivate < now() - '3 months'::interval) OR lastreactivate is null)
	-- Note that we don't filter on 'lastwatch' (although we include it), as it is not a good sign of user liveness - at least, no better than lastlogin (people need to be logged in to watch issues). lastwatch is displayed for informational purposes - if the date is later than lastlogin, it means someone other than user_name added user_name as a watcher after they last logged in.
	AND NOT EXISTS (select * from neverdeactivate where user_name=userlogins.user_name)
ORDER BY lastlogin desc nulls last ;
GRANT select on queries.inactive_users to jira_ro;

-- @provides queries.inactive_users
-- Inactive customer accounts
drop view if exists queries.inactive_users;

CREATE VIEW queries.inactive_users AS
SELECT user_name,
       email_address,
       created,
       lastlogin,
       lastauth,
       lastassign,
       lastwatch,
       lastreactivate
FROM queries.inactive_users_all
WHERE email_address not like '%@mycompany.com'
  AND directory_id=1;
