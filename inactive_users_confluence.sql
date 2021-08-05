-- Lists 'inactive' Confluence user accounts, i.e. accounts that have not logged in or modified a page in 6 months. 
-- This is adapted from the Jira version (inactive_users.sql), with help from https://confluence.atlassian.com/confkb/how-to-identify-inactive-users-in-confluence-214335880.html
-- Last updated: 8/Aug/21
-- See https://www.redradishtech.com/display/KB/Automatically+deactivating+inactive+Jira+users
WITH userlogins AS (select cwd_user.user_name,
                           email_address,
                           cwd_user.created_date,
                           successdate AS lastlogin,
                           cwd_user.directory_id
                    from logininfo
                             JOIN user_mapping ON user_mapping.user_key = logininfo.username
                             JOIN cwd_user ON user_mapping.lower_username = cwd_user.lower_user_name
                             JOIN cwd_membership ON cwd_membership.child_user_id = cwd_user.id
                             JOIN cwd_group ON cwd_membership.parent_id = cwd_group.id
                             JOIN (select distinct permgroupname
                                   from spacepermissions
                                   where spaceid is null) AS spacepermissions
                                  ON spacepermissions.permgroupname = cwd_group.lower_group_name
)
   , lastmods AS (
    select cwd_user.user_name
         , content.lastmoddate AS lastpagemoddate
    from content
             JOIN user_mapping ON user_mapping.user_key = content.lastmodifier
             JOIN cwd_user ON cwd_user.lower_user_name = user_mapping.lower_username
)
   , neverdeactivate AS (
    select cwd_user.user_name
    from cwd_user
             JOIN cwd_membership ON cwd_user.id = cwd_membership.child_user_id
             JOIN cwd_group ON cwd_membership.parent_id = cwd_group.id
    WHERE cwd_group.group_name = 'never-deactivate'
)
SELECT distinct user_name
              , email_address
              , to_char(created_date, 'YYYY-MM-DD')    AS user_created
              , to_char(lastlogin, 'YYYY-MM-DD')       AS lastlogin
              , to_char(lastpagemoddate, 'YYYY-MM-DD') AS lastpagemoddate
FROM userlogins
         LEFT JOIN lastmods USING (user_name)
WHERE (created_date < now() - '6 months'::interval)
  AND ((lastlogin < now() - '6 months'::interval) OR lastlogin is null)
  AND ((lastpagemoddate < now() - '6 months'::interval) OR lastlogin is null)
  AND NOT EXISTS(select * from neverdeactivate where user_name = userlogins.user_name)
ORDER BY lastlogin desc nulls last;
