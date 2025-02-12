/*
  (C) 2013-23 - ntop.org
 */

/*
  Here a list of functions used to check, format data;
  e.g. functions that check if a string is null or empty
 */

/* This function check if value is not set (null or empty).
 * Do not check for 0 as it may be a valid value. */
const QoEQualityBadge = (value) => {
    let badge = ''
    if (value > 90) {
        badge = 'bg-success';
    } else if (value > 75) {
        badge = 'bg-primary'
    } else if (value > 60) {
        badge = 'bg-info'
    } else if (value > 50) {
        badge = 'bg-warning'
    } else {
        badge = 'bg-danger'
    }

    return badge;
}

/* ******************************************************************** */

/* This function check if value is not set (null or empty).
 * Do not check for 0 as it may be a valid value. */
const QoEQualityLabel = (value) => {
    let label = ''
    if (value > 90) {
        label = i18n('flow_details.qoe_excellent_label');
    } else if (value > 75) {
        label = i18n('flow_details.qoe_good_label');
    } else if (value > 60) {
        label = i18n('flow_details.qoe_fair_label');
    } else if (value > 50) {
        label = i18n('flow_details.qoe_degraded_label');
    } else {
        label = i18n('flow_details.qoe_poor_label');
    }

    return label;
}

/* ******************************************************************** */

const dataUtils = function () {
    return {
        QoEQualityBadge,
        QoEQualityLabel,
    };
}();

export default dataUtils;

