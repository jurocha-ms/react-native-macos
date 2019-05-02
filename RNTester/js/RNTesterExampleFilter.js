/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *
 * @format
 * @flow
 */

'use strict';

const React = require('react');
const StyleSheet = require('StyleSheet');
const TextInput = require('TextInput');
const View = require('View');

type Props = {
  filter: Function,
  render: Function,
<<<<<<< HEAD
  /*
   * $FlowFixMe: We shoudl better type this (ideally so that render and filter are
   * aware of what they receive)
   */
  sections: Object,
  disableSearch?: boolean,
=======
  sections: Object,
  disableSearch?: boolean,
  testID?: string,
>>>>>>> v0.59.0
};

type State = {
  filter: string,
};

class RNTesterExampleFilter extends React.Component<Props, State> {
  state = {filter: ''};

  render() {
    const filterText = this.state.filter;
    let filterRegex = /.*/;

    try {
      filterRegex = new RegExp(String(filterText), 'i');
    } catch (error) {
      console.warn(
        'Failed to create RegExp: %s\n%s',
        filterText,
        error.message,
      );
    }

    const filter = example =>
      this.props.disableSearch || this.props.filter({example, filterRegex});

    const filteredSections = this.props.sections.map(section => ({
      ...section,
      data: section.data.filter(filter),
    }));

    return (
<<<<<<< HEAD
      <View>
=======
      <View style={styles.container}>
>>>>>>> v0.59.0
        {this._renderTextInput()}
        {this.props.render({filteredSections})}
      </View>
    );
  }

  _renderTextInput(): ?React.Element<any> {
    if (this.props.disableSearch) {
      return null;
    }
    return (
      <View style={styles.searchRow}>
        <TextInput
          autoCapitalize="none"
          autoCorrect={false}
          clearButtonMode="always"
          onChangeText={text => {
            this.setState(() => ({filter: text}));
          }}
          placeholder="Search..."
          underlineColorAndroid="transparent"
          style={styles.searchTextInput}
<<<<<<< HEAD
          testID="explorer_search"
=======
          testID={this.props.testID}
>>>>>>> v0.59.0
          value={this.state.filter}
        />
      </View>
    );
  }
}

const styles = StyleSheet.create({
  searchRow: {
    backgroundColor: '#eeeeee',
    padding: 10,
  },
  searchTextInput: {
    backgroundColor: 'white',
    borderColor: '#cccccc',
    borderRadius: 3,
    borderWidth: 1,
    paddingLeft: 8,
    paddingVertical: 0,
    height: 35,
  },
<<<<<<< HEAD
=======
  container: {
    flex: 1,
  },
>>>>>>> v0.59.0
});

module.exports = RNTesterExampleFilter;