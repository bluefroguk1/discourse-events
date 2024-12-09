import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@glimmer/tracking";
import EventsCalendarDay from "./events-calendar-day";

export default class EventsCalendarBody extends Component {
  @tracked visibleRange = {
    start: 0,
    end: 20
  };

  get visibleEvents() {
    return this.args.topics.slice(this.visibleRange.start, this.visibleRange.end);
  }

  @action
  updateVisibleRange({ startIndex, endIndex }) {
    this.visibleRange = {
      start: startIndex,
      end: endIndex
    };
  }

  <template>
    <OcclussionCollection
      @items={{@topics}}
      @estimateHeight={{50}}
      @containerSelector=".events-calendar-body"
      @onVisibleItemsChange={{this.updateVisibleRange}}
      as |event|
    >
      <EventsCalendarDay
        @day={{event.day}}
        @topics={{this.visibleEvents}}
        @currentDate={{@currentDate}}
        @currentMonth={{@currentMonth}}
      />
    </OcclussionCollection>
  </template>
}
