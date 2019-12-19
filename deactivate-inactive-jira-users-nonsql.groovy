/**
 * Script that deactivates users who have not logged in within the last 6 months.
 * See https://www.redradishtech.com/pages/viewpage.action?pageId=11796495 
 * Loosely based on Adaptavist's sample at https://www.adaptavist.com/doco/display/SFJ/Automatically+deactivate+inactive+JIRA+users
 * Adaptavist's script has a bug where if a user has *never* logged in, they will never be deactivated. We fix this by checking the user creation date too.
 *
 * Note: I suggest using the SQL variant (deactivate-inactive-jira-users.groovy) of this script in production.
 *
 * jeff@redradishtech.com, 5/Jun/19
 * v1.0
*/
import com.atlassian.crowd.embedded.api.User
import com.atlassian.crowd.embedded.api.CrowdService
import com.atlassian.crowd.embedded.api.UserWithAttributes
import com.atlassian.crowd.embedded.impl.ImmutableUser
import com.atlassian.crowd.embedded.api.SearchRestriction
import com.atlassian.jira.bc.user.UserService
import com.atlassian.jira.component.ComponentAccessor
import com.atlassian.jira.user.ApplicationUser
import com.atlassian.jira.user.ApplicationUsers
import com.atlassian.crowd.search.query.entity.restriction.constants.UserTermKeys
import com.atlassian.crowd.search.query.entity.restriction.constants.DirectoryTermKeys
import com.atlassian.crowd.search.builder.Restriction
import com.atlassian.crowd.search.builder.QueryBuilder
import com.atlassian.crowd.search.query.entity.EntityQuery
import com.atlassian.crowd.search.EntityDescriptor

import org.joda.time.DateTime;
import org.joda.time.Period;

CrowdService crowdService = ComponentAccessor.crowdService

// In a perfect world Jira would let us find exactly the users we want to deactivate with CQL expression 'lastLogin > -6m OR (!lastLogin AND createdDate<-6m)'. Sadly 'lastLogin.lastLoginMillis' is considered a 'secondary' property which Crowd CQL doesn't support (https://developer.atlassian.com/server/crowd/crowd-query-language/). Crowd CQL also doesn't support relative dates like '-6m'. Nor does it support finding users from a particular directory (some of ours may be read-only).
// 
// So instead we search for all active users, and manually check the lastLogin/create date.
// 
// First we search for active users. We don't use UserUtil.getUsers() (unlike every other example on the web), as that returns ApplicationUsers for which it is impossible to get the underlying Ofbiz object, which we need to get the created_date. Instead we use CrowdService.search(), which returns OfBizUsers (https://docs.atlassian.com/software/jira/docs/api/7.2.0/com/atlassian/jira/crowd/embedded/ofbiz/OfBizUser.html).
// QueryBuilder has excellent Javadocs at https://docs.atlassian.com/atlassian-crowd/3.2.3/com/atlassian/crowd/search/builder/QueryBuilder.html
// This returns an iterable of OfBizUsers (https://docs.atlassian.com/software/jira/docs/api/7.2.0/com/atlassian/jira/crowd/embedded/ofbiz/OfBizUser.html) actually
def SearchRestriction active = Restriction.on(UserTermKeys.ACTIVE).exactlyMatching(Boolean.TRUE)
def foundUsers = crowdService.search(
        QueryBuilder.queryFor(User.class, EntityDescriptor.user()).with(active).returningAtMost(EntityQuery.ALL_RESULTS)
        );

log.info "Checking ${foundUsers.size()} active users for possible deactivation-due-to-inactivity"

def shouldDeactivate(User user, DateTime lastUsed) {
        def INACTIVITY_PERIOD = Period.parse("P1Y") // Period of inactivity after which user is deactivated. The format is https://en.wikipedia.org/wiki/ISO_8601#Durations
        // JodaTime 'time ago' calculation: https://stackoverflow.com/a/3859313/7538322
        def expiryDate = lastUsed.plus(INACTIVITY_PERIOD);
        log.info "User ${user.name} will be deactivated after ${expiryDate}";
        return expiryDate.isBeforeNow();
}

def deactivate(User user) {
        UserService userService = ComponentAccessor.getComponent(UserService)
        ApplicationUser updateUser = ApplicationUsers.from(ImmutableUser.newUser(user).active(false).toUser());
        UserService.UpdateUserValidationResult updateUserValidationResult = userService.validateUpdateUser(updateUser);
        if (updateUserValidationResult.isValid()) {
                // Comment out this line to do a dry run:
                userService.updateUser(updateUserValidationResult)
                return true
        } else {
                log.error "Update of ${user.name} failed: ${updateUserValidationResult.getErrorCollection().getErrors().entrySet().join(',')}";
                return false
        }
}

long count = 0
// Restrict to our Internal directory, with ID 1, otherwise we'll get errors trying to modify read-only LDAP users.
foundUsers.findAll { it.directoryId == 1 }.each {
        def ofbizUser = it as com.atlassian.jira.crowd.embedded.ofbiz.OfBizUser;
        def UserWithAttributes user = crowdService.getUserWithAttributes(ofbizUser.getName());
        String lastLoginMillis = user.getValue('login.lastLoginMillis');
        if (lastLoginMillis?.isNumber()) {
                DateTime lastLogin = new DateTime(Long.parseLong(lastLoginMillis));
                if (shouldDeactivate(user, lastLogin) && deactivate(user)) {
                        log.warn "Deactivated ${user.name}, who was last active on ${lastLogin}";
                        count++
                }
        } else if (!lastLoginMillis) {
                DateTime created = new DateTime(ofbizUser.getCreatedDate());
                if (shouldDeactivate(user, created) && deactivate(user)) {
                        log.warn "Deactivated ${user.name}, who has never logged in and was created on ${created}";
                        count++;
                }
        }
}

"${count} inactive users automatically deactivated.\n"

