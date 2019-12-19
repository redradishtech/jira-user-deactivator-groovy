/**
 * Script that deactivates users who have not logged in within the last X months, based on a SQL query.
 * See See https://www.redradishtech.com/pages/viewpage.action?pageId=11796495 
 * 
 * Loosely based on Adaptavist's sample at https://www.adaptavist.com/doco/display/SFJ/Automatically+deactivate+inactive+JIRA+users
 * 
 * Instead of trying to figure out which users to deactivate in code, we instead rely on a queries.inactive_users table or view being defined in the Jira database. The SQL can then be as fancy or customized as needed: e.g. we might want to avoid deactivating role accounts which are assigned issues but never log in. The only requirement for our table or view is that a 'user_name' column must exist.
 *
 * jeff@redradishtech.com, 19/Dec/2019
 * v1.0
*/
import com.atlassian.jira.user.ApplicationUser
import com.atlassian.jira.user.ApplicationUsers
import com.atlassian.jira.bc.user.UserService
import com.atlassian.crowd.embedded.api.User
import com.atlassian.crowd.embedded.api.UserWithAttributes
import com.atlassian.crowd.embedded.api.CrowdService
import com.atlassian.crowd.embedded.impl.ImmutableUser


/** Deactivate a user.
 * @return null on success, or a String error message.
 */
def String deactivate(String user_name) {
        CrowdService crowdService = ComponentAccessor.crowdService
        def UserWithAttributes user = crowdService.getUserWithAttributes(user_name);
        if (!user.active) return "Already inactive";
        UserService userService = ComponentAccessor.getComponent(UserService)
        ApplicationUser updateUser = ApplicationUsers.from(ImmutableUser.newUser(user).active(false).toUser());
        UserService.UpdateUserValidationResult updateUserValidationResult = userService.validateUpdateUser(updateUser);
        if (updateUserValidationResult.isValid()) {
                // Comment out this line to do a dry run:
                userService.updateUser(updateUserValidationResult)
                return null
        } else {
                return updateUserValidationResult.getErrorCollection().getErrors().entrySet().join(',')
        }
}

// https://scriptrunner.adaptavist.com/latest/jira/recipes/misc/connecting-to-databases.html
import com.atlassian.jira.component.ComponentAccessor
import groovy.sql.Sql
import org.ofbiz.core.entity.ConnectionFactory
import org.ofbiz.core.entity.DelegatorInterface

import java.sql.Connection

def delegator = (DelegatorInterface) ComponentAccessor.getComponent(DelegatorInterface)
String helperName = delegator.getGroupHelperName("default")

def sqlStmt = """select * from queries.inactive_users;"""

Connection conn = ConnectionFactory.getConnection(helperName)
Sql sql = new Sql(conn)

log.warn "Beginning inactive user deactivation run"
long count = 0
try {
    sql.eachRow(sqlStmt) {
    // https://stackoverflow.com/questions/50041526/how-to-read-each-row-in-a-groovy-sql-statement
        def errmsg = deactivate(it['user_name'] as String);
        if (!errmsg) {
                log.warn "Deactivated ${it['user_name']}: ${it}";
                count++
        } else {
                log.error "Failed to deactivate ${it['user_name']}: ${errmsg}";
        }
    }
}
finally {
    sql.close()
}
"${count} inactive users automatically deactivated.\n"
