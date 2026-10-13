require "rails_helper"

RSpec.describe "Content limits", type: :request do
  let(:user) { User.create!(name: "Reader", email: "content-limits@example.com", password: "password123!") }
  let(:friend) { User.create!(name: "Friend", email: "content-limits-friend@example.com", password: "password123!") }
  let(:book) { Book.create!(title: "Content limits book", authors_text: "Author") }
  let(:group) { Group.create!(group_admin: user, name: "Readers", group_type: :public_group, lifecycle_status: :active) }
  let(:source) { user.jjaeks.create!(content: "Source") }

  before { sign_in user }

  it "provides the same character limit UI on Jjaek and comment create and edit forms" do
    BookFriendship.create!(requester: user, addressee: friend, status: :accepted)
    user.bookshelf_entries.create!(book:)
    source.comments.create!(user:, content: "Editable comment")
    group_source = user.jjaeks.create!(group:, content: "Group source")

    [ root_path, user_path(friend), group_path(group), book_path(book), book_path(book, group_id: group.id),
      new_jjaek_path, new_jjaek_path(quoted_jjaek_id: source.id),
      new_group_jjaek_path(group, quoted_jjaek_id: group_source.id),
      edit_jjaek_path(source), edit_jjaek_path(group_source), jjaek_path(source) ].each do |path|
      get path
      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML(response.body)
      inputs = page.css('textarea[name="jjaek[content]"], textarea[name="comment[content]"]')
      expect(inputs).not_to be_empty
      inputs.each do |input|
        field = input.parent
        expect(field["data-controller"]).to eq("content-length")
        expect(field["data-content-length-limit-value"]).to eq("200")
        expect(field.text).not_to include("최대 200자 · 공백과 문장부호 포함")
        counter = field.at_css('[data-content-length-target="counter"]')
        expect(counter.text).to eq("#{input.text.delete_prefix("\n").length} / 200")
        expect(counter["class"]).to include("text-stone-400")
        expect(field.at_css('[data-content-length-target="errors"]')["hidden"]).not_to be_nil
        expect(input["maxlength"]).to be_nil
      end
    end
  end

  it "accepts 200-character Jjaeks and rejects a 201-character edit while preserving the input" do
    content = "🙂" * 200
    post jjaeks_path, params: { jjaek: { content: } }
    created = user.jjaeks.last
    expect(created.content).to eq(content)
    expect(response).to redirect_to(jjaek_path(created))

    content = "한" * 200
    patch jjaek_path(created), params: { jjaek: { content: } }
    expect(response).to redirect_to(jjaek_path(created))
    expect(created.reload.content).to eq(content)

    patch jjaek_path(created), params: { jjaek: { content: content + "!" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(created.reload.content).to eq(content)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css('textarea[name="jjaek[content]"]').text.delete_prefix("\n")).to eq(content + "!")
    expect(page.text).to include("내용은 200자 이하로 입력해 주세요.")
    field = page.at_css('[data-controller="content-length"]')
    expect(field.at_css('[data-content-length-target="counter"]').text).to eq("201 / 200")
    expect(field.at_css('[data-content-length-target="counter"]')["class"]).to include("text-red-700")
    expect(field.at_css('[data-content-length-target="serverErrors"]').text.strip).to eq("")
    expect(field.at_css('[data-content-length-target="warning"]')["hidden"]).to be_nil
    expect(field.text.scan("내용은 200자 이하로 입력해 주세요.").size).to eq(1)
  end

  it "keeps the 200-character comment boundary on create and update" do
    content = "🙂" * 200
    post jjaek_comments_path(source), params: { comment: { content: } }
    created = source.comments.last
    expect(created.content).to eq(content)
    expect(response).to redirect_to(jjaek_path(source))

    patch jjaek_comment_path(source, created), params: { comment: { content: "한" * 200 } }
    expect(response).to redirect_to(jjaek_path(source))
    expect(created.reload.content).to eq("한" * 200)

    expect {
      post jjaek_comments_path(source), params: { comment: { content: content + "!" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    }.not_to change(Comment, :count)
    expect(response).to have_http_status(:unprocessable_content)
    page = Nokogiri::HTML(response.body)
    textarea = page.at_css(%(form[action="#{jjaek_comments_path(source)}"] textarea[name="comment[content]"]))
    expect(textarea.text.delete_prefix("\n")).to eq(content + "!")
    field = textarea.ancestors('[data-controller="content-length"]').first
    expect(field).to be_present
    warnings = field.css('[data-content-length-target="warning"]')
    expect(warnings.size).to eq(1)
    expect(warnings.first.text.strip).to eq("내용은 200자 이하로 입력해 주세요.")
    expect(warnings.first["hidden"]).to be_nil
    expect(field.at_css('[data-content-length-target="serverErrors"]').text.strip).to eq("")

    patch jjaek_comment_path(source, created), params: { comment: { content: content + "!" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(created.reload.content).to eq("한" * 200)
    page = Nokogiri::HTML(response.body)
    textarea = page.at_css(%(form[action="#{jjaek_comment_path(source, created)}"] textarea[name="comment[content]"]))
    expect(textarea.text.delete_prefix("\n")).to eq(content + "!")
    field = textarea.ancestors('[data-controller="content-length"]').first
    expect(field).to be_present
    warnings = field.css('[data-content-length-target="warning"]')
    expect(warnings.size).to eq(1)
    expect(warnings.first.text.strip).to eq("내용은 200자 이하로 입력해 주세요.")
    expect(warnings.first["hidden"]).to be_nil
    expect(field.at_css('[data-content-length-target="serverErrors"]').text.strip).to eq("")
  end

  it "keeps the server blank-content error separate from the hidden length warning" do
    post jjaeks_path, params: { jjaek: { content: "" } }

    expect(response).to have_http_status(:unprocessable_content)
    page = Nokogiri::HTML(response.body)
    field = page.at_css('[data-controller="content-length"]')
    expect(field.at_css('[data-content-length-target="serverErrors"]').text).to eq("내용을 입력해 주세요.")
    expect(field.at_css('[data-content-length-target="errors"]')["hidden"]).to be_nil
    expect(field.at_css('[data-content-length-target="warning"]')["hidden"]).not_to be_nil
    expect(field.at_css('[data-content-length-target="counter"]').text).to eq("0 / 200")
    expect(field.at_css('[data-content-length-target="counter"]')["class"]).to include("text-stone-400")
  end
end
