import Component from '@glimmer/component';
import { action } from "@ember/object";
import { debug } from '@ember/debug';
import { guidFor } from '@ember/object/internals';

import uPlot from 'uplot';
import seriesBarsPlugin from './uplot/seriesbars-plugin';

//import 'uplot/dist/uPlot.min.css';
//import wheelZoom from './chart/plugin-wheelzoom.js'

/**
...

```html
<OxiBase::Chart .../>
```

@module oxi-base/chart
@param list { array } - List of hashes defining the options.
*/

export default class OxiChartComponent extends Component {
    guid;
    options;
    data;

    // x - timestamp
    // y - BTC price
    // y - RSI
    // y - RSI MA

    constructor() {
        super(...arguments);

        this.guid = guidFor(this);
        /*
         * Options
         */
        // Evaluate given options and set defaults
        const {
            width = 400,
            height = 200,
            title = "",
            cssClass = "",
            x_is_timestamp = true,
            y_values = [],
            legend_label = true,
            legend_value = false,
            legend_date_format = '{YYYY}-{MM}-{DD}, {HH}:{mm}:{ss}',
            type = 'line',
            bar_group_labels,
            bar_vertical = false,
        } = this.args.options;

        // assemble uPlot options
        let uplotOptions = {
            width,
            height,
            title,
            class: cssClass,
            legend: {
                show: legend_label,
                live: legend_value,
            },
            scales: {
                x: {
                    time: x_is_timestamp,
                },
            },
            series: [
                {}, // the x values
            ],
        };

        /*
         * LINE chart
         */
        // set custom date format
        if (type == 'line' && x_is_timestamp) {
            // format strings: https://github.com/leeoniya/uPlot/blob/1.6.3/src/fmtDate.js#L74
            let dateFormatter = uPlot.fmtDate(legend_date_format);
            uplotOptions.series[0].value = (self, rawValue) => rawValue == null ? "-" : dateFormatter(new Date(rawValue * 1000));
        }

        /*
         * BAR chart
         */
        if (type == 'bar') {
            uPlot.assign(uplotOptions, {
                scales: {
                    x: {
                        time: false,
                    },
                    'auto': {
                        auto: true,
                    },
                    '%': {
                        auto: false,
                        range: (self) => [ 0, 100 ],
                    },
                },
                axes: [
                    {},
                    { show: false },
                ],
                plugins: [
                    seriesBarsPlugin({
                        labels: () => this.args.data.map(group => bar_group_labels ? bar_group_labels[group[0]] : group[0]), // group / time series
                        ori: bar_vertical ? 1 : 0,
                        dir: 1,
                    }),
                ],
            });
        }

        /*
         * Series
         */
        let autoScaleId = 0;

        for (const graph of this.args.options.y_values) {
            const {
                label = '',
                color = undefined,
                line_width = 1,
                scale = 'auto',
            } = graph;

            let autogenScale;
            if (Array.isArray(scale)) {
                autogenScale = `_autogenerated_${++autoScaleId}`;
                uplotOptions.scales[autogenScale] = {
                    auto: false,
                    range: () => scale,
                };
            }

            let seriesOpts = {
                label,
                scale: autogenScale ? autogenScale : scale,
                width: line_width/window.devicePixelRatio,
                //value: (self, rawValue) => rawValue == null ? "-" : rawValue.toFixed(0),
            }
            if (type == 'line') {
                seriesOpts.stroke = color;
            }
            if (type == 'bar') {
                seriesOpts.fill = color;
            }
            uplotOptions.series.push(seriesOpts);
        }

        this.options = uplotOptions;

        /*
         * Convert data from
         * from [ [x1, price1, rsi1], [x2, price2, rsi2] ]
         *   to [ [x1, x2], [price1, price2], [rsi1, rsi2] ]
         */
        this.data = [];
        for (let i=0; i<this.args.data[0].length; i++) {
            this.data.push(this.args.data.map(row => +row[i]));
        }
    }

    @action
    plot(element) {
        // new uPlot(this.options, this.data, (uplot, init) => {
        new uPlot(this.options, this.data, (uplot, init) => {
            element.appendChild(uplot.root);
            init();
        })
    }
}
