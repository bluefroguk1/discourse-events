let eventLabel = function(event, args = {}) {
  const icon = Discourse.SiteSettings.events_event_label_icon;
  const longFormat = Discourse.SiteSettings.events_event_label_format;
  const shortFormat = Discourse.SiteSettings.events_event_label_short_format;
  const shortOnlyStart = Discourse.SiteSettings.events_event_label_short_only_start;
  const includeTimeZone = Discourse.SiteSettings.events_event_label_include_timezone;

  let label = `<i class='fa fa-${icon}'></i>`;

  if (!args.mobile) {
    let start = moment(event['start']);
    let end = moment(event['end']);
    let allDay = false;

    if (event['start'] && event['end']) {
      const startIsDayStart = start.hour() === 0 && start.minute() === 0;
      const endIsDayEnd = end.hour() === 23 && end.minute() === 59;
      allDay = startIsDayStart && endIsDayEnd;
    }

    let format = args.short ? shortFormat : longFormat;
    let formatArr = format.split(',');
    if (allDay) format = formatArr[0];
    let dateString = start.format(format);

    if (event['end'] && (!args.short || !shortOnlyStart)) {
      const diffDay = start.date() !== end.date();
      if (!allDay || diffDay) {
        const endFormat = (diffDay || allDay) ? format : formatArr[formatArr.length - 1];
        dateString += ` – ${end.format(endFormat)}`;
      }
    }

    if (includeTimeZone) {
      dateString += `, ${start.format('Z')}`;
    }

    label += `<span>${dateString}</span>`;
  }

  return label;
};

let utcDateTime = function(dateTime) {
  return moment.parseZone(dateTime).utc().format().replace(/-|:|\.\d\d\d/g,"");
};

let googleUri = function(params) {
  let href = "https://www.google.com/calendar/render?action=TEMPLATE";

  if (params.title) {
    href += `&text=${params.title.replace(/ /g,'+').replace(/[^\w+]+/g,'')}`;
  }

  href += `&dates=${utcDateTime(params.event.start)}/${utcDateTime(params.event.end)}`;

  href += `&details=${params.details || I18n.t('add_to_calendar.default_details', {url: params.url})}`;

  if (params.location) {
    href += `&location=${params.location}`;
  }

  href += "&sf=true&output=xml";

  return href;
};

let icsUri = function(params) {
  return encodeURI(
    'data:text/calendar;charset=utf8,' + [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'BEGIN:VEVENT',
      'URL:' + document.URL,
      'DTSTART:' + (utcDateTime(params.event.start) || ''),
      'DTEND:' + (utcDateTime(params.event.end) || ''),
      'SUMMARY:' + (params.title || ''),
      'DESCRIPTION:' + (params.details || ''),
      'LOCATION:' + (params.location || ''),
      'END:VEVENT',
      'END:VCALENDAR'
    ].join('\n'));
};

let allDay = function(attrs, topic) {
  attrs['classes'] = 'all-day';
  attrs['allDay'] = true;

  if (topic.category) {
    attrs['listStyle'] += `background-color: #${topic.category.color};`;
  }

  return attrs;
};

let allDayPrevious = false;

let eventsForDay = function(day, topics, args = {}) {
  let allDayCount = 0;

  return topics.reduce((filtered, topic) => {
    if (topic.event) {
      const start = moment(topic.event.start);
      const end = moment(topic.event.end);
      const startIsDayStart = start.hour() === 0 && start.minute() === 0;
      const endIsDayEnd = end.hour() === 23 && end.minute() === 59;
      const isAllDay = startIsDayStart && endIsDayEnd;

      let attrs = {
        topicId: topic.id,
        listStyle: ''
      };

      if (day.isSame(start, "day")) {
        if (isAllDay) {
          attrs = allDay(attrs, topic);
        } else {
          attrs['time'] = moment(topic.event.start).format('h:mm a');

          if (topic.event.end && !day.isSame(end, "day")) {
            attrs = allDay(attrs, topic);
          } else if (topic.category) {
            attrs['dotStyle'] = Ember.String.htmlSafe(`color: #${topic.category.color}`);
          }
        }

        attrs['title'] = topic.title;

        filtered.push(attrs);
      } else if (topic.event.end && (day.isSame(end, "day") || day.isBetween(topic.event.start, topic.event.end, "day"))) {

        allDayCount ++;
        if (!topic.event.allDayIndex) topic.event.allDayIndex = allDayCount;
        if (!args.dateEvents && !allDayPrevious && (topic.event.allDayIndex !== allDayCount)) {
          let difference = topic.event.allDayIndex - allDayCount;
          attrs['listStyle'] += `margin-top: ${difference * 22}px;`;
        }
        allDayPrevious = true;

        attrs = allDay(attrs, topic);

        if (args.dateEvents || args.expanded || args.firstDay)   {
          attrs['title'] = topic.title;
        }

        if (attrs['listStyle'].length) {
          attrs['listStyle'] = Ember.String.htmlSafe(attrs['listStyle']);
        }

        filtered.push(attrs);
      } else if (isAllDay) {
        allDayPrevious = false;
      }
    }

    return filtered;
  }, []);
};

export { eventLabel, googleUri, icsUri, eventsForDay };
