# encoding: utf-8
module NodeHelper
  ContentPresenter = Struct.new(:record, :title, :meta, :tags, :notice, :image, :body, :actions, :css_class, :hidden) do
    def to_hash
      attrs = members.map(&:to_sym)
      Hash[*attrs.zip(values).flatten(1)]
    end

    def self.collection?
      !!@collection
    end

    def self.collection(&blk)
      @collection = true
      yield
    ensure
      @collection = false
    end
  end

  def article_for(record)
    cp = ContentPresenter.new
    cp.record = record
    cp.hidden = ContentPresenter.collection? && record.score < 0
    cp.hidden = false if current_account.try(:show_negative_nodes)
    cp.css_class = %w(node hentry)
    score = [ [record.node.score / 5, -10].max, 10].min
    cp.css_class << "score#{score}"
    cp.css_class << record.class.name.downcase
    cp.css_class << 'new-node' if current_account && record.node.read_status(current_account) == :not_read
    cp.css_class << 'ppp' if record.node.on_ppp?
    cp.css_class << "preview" if @preview_mode
    yield cp
    cp.meta ||= posted_by(record)
    cp.tags ||= tags_for(record.node)
    cp.body ||= (ContentPresenter.collection? ?
                 record.truncated_body.sub("[...](suite)", " " + link_to("(…)", path_for_content(record))).html_safe :
                 record.body)
    render 'nodes/content', cp.to_hash
  end

  def tags_for(node)
    if current_user
      his_tags = current_user.taggings.
                             where(node_id: node.id).
                             order(created_at: :desc).
                             map(&:tag).each {|t| t.tagged_by_current = true }
      if his_tags.any?
        other_tags = node.popular_tags.where("tags.id NOT IN (?)", his_tags.map(&:id))
        return his_tags + other_tags
      end
    end
    node.popular_tags
  end

  def link_to_content(content)
    link_to content.title, path_for_content(content)
  end

  def filter_pagination_params(allowed_params)
    allowed_params += ['action', 'controller']
    params.each do |k,v|
      if allowed_params.include?(k)
        params[k] = v
      else
        params[k] = nil
      end
    end
  end

  def paginated_nodes(nodes, link=nil)
    paginated_section(nodes, link) do
      content_tag(:main, render(nodes.map &:content), id: 'contents', role: 'main')
    end
  end

  def paginated_contents(contents, link=nil)
    paginated_section(contents, link) do
      content_tag(:main, render(contents), id: 'contents', role: 'main')
    end
  end

  def paginated_section(args, link=nil, &block)
    toolbox    = ''.html_safe
    @feeds.each do |k,v|
      toolbox += content_tag(:div, link_to(v, k), class: "follow_feed")
    end
    toolbox   += content_tag(:div, link, class: 'new_content') if link
    order_bar  = render 'shared/order_navbar'
    pagination = paginate(args, inner_window: 10).to_s
    before = content_tag(:nav, toolbox + order_bar + pagination, class: "toolbox")
    after  = content_tag(:nav, pagination, class: "toolbox")
    ContentPresenter.collection do
      before + capture(&block) + after
    end
  end

  def date_pour_css(content)
    date_time = content.node.try(:created_at) || Time.now
    content_tag(:div, date_time.day, class: "jour") +
    content_tag(:div, I18n.l(date_time, format: "%b"), class: "mois") +
    content_tag(:div, date_time.year, class: "annee")
  end

  def posted_by(content, user_link='Anonyme')
    user   = content.user
    user ||= current_user if content.new_record?
    if user
      user_link  = link_to(user.name, "/users/#{user.cached_slug}", rel: 'author')
      user_infos = []
      user_infos << homesite_link(user)
      user_infos << jabber_link(user)
      user_infos << mastodon_link(user)
      user_infos.compact!
      user_link += (" (" + user_infos.join(', ') + ")").html_safe  if user_infos.any?
    end
    date_time    = content.is_a?(Comment) ? content.created_at : content.node.try(:created_at)
    date_time  ||= Time.now
    published_at = content_tag(:time, "le #{date_time.to_fs(:posted)}", datetime: date_time.iso8601, class: "updated")
    caption      = content_tag(:span, "", class: "floating_spacer") +
                   content_tag(:span, "Posté par #{ user_link } #{ published_at }.".html_safe, class: "posted_by_spanblock")
    caption.html_safe
  end

  def read_it(content)
    node = content.node
    path = path_for_content(content)
    link = link_to_unless_current(content.label_for_expand, path, itemprop: "url") { "" }
    ret  = tag(:meta, itemprop: "interactionCount", content: "UserComments:#{node.try(:comments_count)}")
    nb_comments = content_tag(:span, pluralize(node.try(:comments_count), "commentaire"), class: "nb_comments")
    if current_account
      status = node.read_status(current_account)
      visit  = case status
               when :not_read then ", non visité"
               when Integer   then ", #{pluralize status, "nouveau", "nouveaux"} !"
               else                ", déjà visité"
               end
      visit  = content_tag(:span, visit, class: "visit")
      status = :new_comments if Integer === status
    else
      status = :anonymous_reader
    end
    ret += content_tag(:span, "#{link} (#{nb_comments}#{visit}).".html_safe, class: status)
    if current_account && ([:no_comments, :new_comments, :read].include?(status) || (content.persisted? && current_page?(path)))
      ret += content_tag(:span, class: "action") do
        button_to("Oublier", reading_path(id: node.id), method: :delete, remote: true, class: "unread")
      end
    end
    ret
  end

  def cc_url(content)
    date = content.created_at || Date.today
    version = date.year < 2014 ? "3.0" : "4.0"
    "http://creativecommons.org/licenses/by-sa/#{version}/deed.fr"
  end

  def translate_content_type(content_type)
    t "activerecord.models.#{content_type.downcase}"
  end

  # This variant translates "to news", "to diary", etc. to be included in a
  # constructed sentance, because "à la dépêche" and "au journal" are not
  # automatically constructable from the translated model name alone.
  def translate_to_content_type(content_type)
    t "activerecord.to_models.#{content_type.downcase}"
  end
end
