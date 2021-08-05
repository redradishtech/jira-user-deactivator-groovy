-- Lists 'inactive' Confluence user accounts, i.e. accounts that have not logged in or modified a page in 6 months. 
-- This is adapted from the Jira version (inactive_users.sql), with help from https://confluence.atlassian.com/confkb/how-to-identify-inactive-users-in-confluence-214335880.html
-- Last updated: 8/Aug/21
-- See https://www.redradishtech.com/display/KB/Automatically+deactivating+inactive+Jira+users
WITH users AS (
    select cwd_user.*, cwd_directory.directory_name
    from cwd_user
             JOIN cwd_directory ON cwd_user.directory_id = cwd_directory.id
    WHERE cwd_user.active = 'T'
)
   , userlogins AS (select users.user_name,
                           email_address,
                           directory_name,
                           users.created_date,
                           successdate AS lastlogin,
                           users.directory_id
                    from logininfo
                             JOIN user_mapping ON user_mapping.user_key = logininfo.username
                             JOIN users ON user_mapping.lower_username = users.lower_user_name
                             JOIN cwd_membership ON cwd_membership.child_user_id = users.id
                             JOIN cwd_group ON cwd_membership.parent_id = cwd_group.id
                             JOIN (select distinct permgroupname
                                   from spacepermissions
                                   where spaceid is null) AS spacepermissions
                                  ON spacepermissions.permgroupname = cwd_group.lower_group_name
)
   , lastmods AS (
    select distinct users.user_name
                  , max(content.lastmoddate) AS lastpagemoddate
    from content
             JOIN user_mapping ON user_mapping.user_key = content.lastmodifier
             JOIN users ON users.lower_user_name = user_mapping.lower_username
       group by user_name
)
   , neverdeactivate AS (
    select cwd_user.user_name
    from cwd_user
             JOIN cwd_membership ON cwd_user.id = cwd_membership.child_user_id
             JOIN cwd_group ON cwd_membership.parent_id = cwd_group.id
    WHERE cwd_group.group_name = 'never-deactivate'
)
SELECT distinct '[~' || user_name || ']'
              , email_address
              , to_char(created_date, 'YYYY-MM-DD')    AS user_created
              , to_char(lastlogin, 'YYYY-MM-DD')       AS lastlogin
              , to_char(lastpagemoddate, 'YYYY-MM-DD') AS lastpagemoddate
              , directory_name
FROM userlogins
         LEFT JOIN lastmods USING (user_name)
WHERE (created_date < now() - '6 months'::interval)
  AND ((lastlogin < now() - '6 months'::interval) OR lastlogin is null)
  AND ((lastpagemoddate < now() - '6 months'::interval) OR lastlogin is null)
  AND NOT EXISTS(select * from neverdeactivate where user_name = userlogins.user_name)
ORDER BY lastlogin desc nulls last;
