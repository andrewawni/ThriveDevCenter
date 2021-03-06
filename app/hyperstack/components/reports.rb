# frozen_string_literal: true

# Single table line
class ReportItem < HyperComponent
  include Hyperstack::Router::Helpers

  param :report
  render(TR) do
    TD { @Report.game_version.to_s }
    TH(scope: 'row') { Link("/report/#{@Report.id}") { @Report.id.to_s } }
    TD { Link("/report/#{@Report.id}") { @Report.updated_at.to_s } }
    TD { @Report.solved ? 'yes' : 'no' }
    # TD{"#{@Report.crash_time}"}
    TD { @Report.description.to_s }
    TD { @Report.public.to_s }
    TD { @Report.solved_comment.to_s }
  end
end

# A table of crash reports
class Reports < HyperComponent
  include Hyperstack::Router::Helpers
  include ComponentUrlParamHelper

  param :current_page, default: 0, type: Integer
  param :page_size, default: 25, type: Integer

  attr_accessor :CurrentPage, :PageSize, :show_solved, :show_duplicates, :sort_by, :order,
                :search_text

  before_mount do
    @sort_by = :updated_at
    @order = :desc
    @show_solved = true
    @show_duplicates = true
    @show_matching_text = ''
    @search_text = ''

    set_values_from_query url_param_config, location.query

    @show_matching_text = @search_text unless @search_text.blank?
  end

  def items
    scope = Report.visible_to(Hyperstack::Application.acting_user_id)

    scope = scope.not_solved unless @show_solved

    scope = scope.not_duplicate unless @show_duplicates

    scope = scope.contains_text @search_text unless @search_text.blank?

    if @sort_by == :updated_at && @order == :desc
      scope.index_by_updated_at
    elsif @sort_by == :updated_at && @order == :asc
      scope.index_by_updated_at_reverse
    elsif @sort_by == :id && @order == :asc
      scope.index_id
    elsif @sort_by == :id && @order == :desc
      scope.index_id_reverse
    else
      scope
    end
  end

  def list_management_components
    RS.Form(:inline) {
      RS.FormGroup(class: 'row') {
        RS.FormGroup(:inline, class: 'col-12 col-md-auto') {
          RS.Label(for: 'sortReportsBy', class: 'sm') { 'sort by' }
          RS.Input(type: :select, id: 'sortReportsBy', value: value_from_sort_by) {
            OPTION(value: '1') { 'Updated At' }
            OPTION(value: '2') { 'ID' }
          }.on(:change) { |e|
            @sort_by = if e.target.value == '1'
                         :updated_at
                       else
                         :id
                       end
            update_url
          }

          RS.Input(type: :select, value: value_from_order) {
            OPTION(value: '2') { 'Descending' }
            OPTION(value: '1') { 'Ascending' }
          }.on(:change) { |e|
            @order = if e.target.value == '1'
                       :asc
                     else
                       :desc
                     end
            update_url
          }
        }
        RS.FormGroup(:inline, class: 'col-6 col-md-auto') {
          RS.Label(:check, 'sm') {
            RS.Input(type: :checkbox, checked: @show_solved).on(:change) { |e|
              @show_solved = e.target.checked
              update_url
            }
            'show solved'
          }
        }
        RS.FormGroup(:inline, class: 'col-6 col-md-auto') {
          RS.Label(:check, 'sm') {
            RS.Input(type: :checkbox, checked: @show_duplicates).on(:change) { |e|
              @show_duplicates = e.target.checked
              update_url
            }
            'show duplicates'
          }
        }
        RS.FormGroup(:inline, class: 'col-12 col-md-auto') {
          RS.Label(className: 'sm') {
            'Contains:'
          }
          RS.Input(value: @show_matching_text) {}.on(:change) { |e|
            mutate @show_matching_text = e.target.value
          }
          RS.Button(colour: 'secondary', disabled: @show_matching_text.blank?) {
            'Search'
          } .on(:click) {
            @search_text = @show_matching_text
            update_url
          }
        }
      }
    }.on(:submit) { |e|
      e.prevent_default
      @search_text = @show_matching_text
      update_url
    }
  end

  def value_from_order
    if @order == :asc
      '1'
    elsif @order == :desc
      '2'
    else
      puts 'invalid order'
      '2'
    end
  end

  def value_from_sort_by
    if @sort_by == :updated_at
      '1'
    elsif @sort_by == :id
      '2'
    else
      puts 'invalid sort_by'
      '1'
    end
  end

  def url_param_config
    {
      CurrentPage: {
        param: 'page',
        type: 'to_i',
        default: 0
      },
      PageSize: {
        param: 'page_size',
        type: 'to_i',
        default: 25
      },
      show_solved: {
        param: 'solved',
        type: ->(v) { ComponentUrlParamHelper.parse_bool v },
        default: true
      },
      show_duplicates: {
        param: 'duplicates',
        type: ->(v) { ComponentUrlParamHelper.parse_bool v },
        default: true
      },
      sort_by: {
        param: 'sort_by',
        type: 'to_sym',
        default: :updated_at
      },
      order: {
        param: 'order',
        type: 'to_sym',
        default: :desc
      },
      search_text: {
        param: 'search',
        type: 'to_s',
        default: ''
      }
    }
  end

  def update_url
    url_params = build_query_from_values url_param_config
    history.push location.pathname + url_params ? "?#{url_params}" : ''
  end

  render(DIV) do
    H1 { 'Crash reports' }

    BR {}

    list_management_components

    BR {}

    Paginator(current_page: @CurrentPage,
              page_size: @PageSize,
              item_count: items.count,
              ref: set(:paginator)) {
      # This is set with a delay
      if @paginator
        RS.Table(:striped, :responsive) {
          THEAD {
            TR {
              TH { 'Version' }
              TH { 'ID' }
              TH { 'Updated At' }
              TH { 'Solved' }
              # TH{ "Crash Time" }
              TH { 'Description' }
              TH { 'Public' }
              TH { 'Solve comment' }
            }
          }

          TBODY {
            items.paginated(@paginator.offset, @paginator.take_count).each { |report|
              ReportItem(report: report)
            }
          }
        }
      end
    }.on(:page_changed) { |page|
      @CurrentPage = page
      update_url
    }.on(:created) {
      mutate {}
    }
  end
end
