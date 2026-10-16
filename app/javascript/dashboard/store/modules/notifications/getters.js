import { sortComparator } from './helpers';
import camelcaseKeys from 'camelcase-keys';

const filterNotificationRecord = (notification, filters = {}) => {
  const { type = '', status = '', currentConversationId } = filters;
  const isRead = Boolean(notification.read_at);
  const isConversationResolved =
    notification.primary_actor?.status === 'resolved';

  // If "read" is not included in the filter, exclude read notifications and resolved conversations.
  // Exception: keep the currently active conversation in view while it's still open (not resolved)
  // so opening it to read/reply doesn't make it abruptly vanish mid-viewing.
  if (type !== 'read') {
    if (isConversationResolved) {
      return false;
    }
    if (isRead) {
      const actorId = Number(
        notification.primary_actor_id || notification.primary_actor?.id
      );
      const isCurrentlyActive =
        currentConversationId && actorId === Number(currentConversationId);

      if (!isCurrentlyActive) {
        return false;
      }
    }
  }

  // If "snoozed" is not included in the filter, exclude active snoozed notifications
  if (status !== 'snoozed' && notification.snoozed_until) {
    const isSnoozedActive = new Date(notification.snoozed_until) > new Date();
    if (isSnoozedActive) {
      return false;
    }
  }

  return true;
};

export const getters = {
  getNotifications($state) {
    return Object.values($state.records).sort((n1, n2) => n2.id - n1.id);
  },
  getFilteredNotifications: $state => (filters = {}) => {
    const { sortOrder: rawSortOrder = 'desc' } = filters;
    const sortOrder = rawSortOrder === 'desc' ? 'newest' : 'oldest';
    const sortedNotifications = Object.values($state.records)
      .filter(n => filterNotificationRecord(n, filters))
      .sort((n1, n2) => sortComparator(n1, n2, sortOrder));
    return sortedNotifications;
  },
  getFilteredNotificationsV4: $state => (filters = {}) => {
    const { sortOrder: rawSortOrder = 'desc' } = filters;
    const sortOrder = rawSortOrder === 'desc' ? 'newest' : 'oldest';
    const sortedNotifications = Object.values($state.records)
      .filter(n => filterNotificationRecord(n, filters))
      .sort((n1, n2) => sortComparator(n1, n2, sortOrder));
    return camelcaseKeys(sortedNotifications, { deep: true });
  },
  getNotificationById: $state => id => {
    return $state.records[id] || {};
  },
  getUIFlags($state) {
    return $state.uiFlags;
  },
  getNotification: $state => id => {
    const notification = $state.records[id];
    return notification || {};
  },
  getMeta: $state => {
    return $state.meta;
  },
  getNotificationFilters($state) {
    return $state.notificationFilters;
  },
  getHasUnreadNotifications: $state => {
    return $state.meta.unreadCount > 0;
  },
  getUnreadCount: $state => {
    return $state.meta.unreadCount;
  },
};
