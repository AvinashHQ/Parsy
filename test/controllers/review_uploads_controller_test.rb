# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "zip"

class ReviewUploadsControllerTest < ActionDispatch::IntegrationTest
  PDF_BYTES = "%PDF-1.7\n1 0 obj\n<< /Type /Catalog >>\nendobj\n%%EOF".b

  setup do
    @tenant = Tenant.create!(name: "Upload Controller Tenant", slug: "upload-controller-#{SecureRandom.hex(4)}")
    @other_tenant = Tenant.create!(name: "Other Upload Tenant", slug: "other-upload-#{SecureRandom.hex(4)}")
    @user = User.create!(tenant: @tenant, email: "upload-operator@example.test", name: "Upload Operator", operator_token: "upload-token")
    @tempfiles = []
  end

  teardown do
    @tempfiles.each do |tempfile|
      tempfile.close!
    rescue StandardError
      nil
    end
  end

  test "authenticated operator can open upload screen" do
    sign_in

    get new_review_upload_path

    assert_response :success
    assert_select "section[aria-label='Upload invoices']"
    assert_select "form[action='#{review_upload_path}']"
    assert_select "input[type='file'][name='upload[file]']"
    assert_select "button", text: "Upload invoices"
  end

  test "unauthenticated upload screen redirects to sign in" do
    get new_review_upload_path

    assert_redirected_to new_session_path
  end

  test "unauthenticated upload post redirects and stores nothing" do
    assert_no_difference -> { Review::Batch.count } do
      assert_no_difference -> { Review::Document.count } do
        assert_no_difference -> { ActiveStorage::Blob.count } do
          post review_upload_path, params: { upload: { file: uploaded_file("invoice.pdf", "application/pdf", PDF_BYTES) } }
        end
      end
    end

    assert_redirected_to new_session_path
  end

  test "signed in upload ignores hostile tenant params" do
    sign_in

    assert_difference -> { Review::Batch.where(tenant: @tenant).count }, 1 do
      assert_no_difference -> { Review::Batch.where(tenant: @other_tenant).count } do
        post review_upload_path, params: {
          tenant_id: @other_tenant.id,
          upload: {
            tenant_id: @other_tenant.id,
            name: "Hostile Tenant Upload",
            file: uploaded_file("invoice.pdf", "application/pdf", PDF_BYTES)
          }
        }
      end
    end

    batch = Review::Batch.where(tenant: @tenant).order(:created_at).last
    assert_redirected_to review_batch_path(batch)
    assert_equal @tenant, batch.tenant
    assert_equal 1, batch.documents.count
  end

  test "zip upload redirects to batch with content free flash counts" do
    sign_in

    post review_upload_path, params: {
      upload: {
        name: "Controller ZIP Upload",
        file: uploaded_file("invoices.zip", "application/zip", zip_bytes([
          [ "invoice.pdf", PDF_BYTES ],
          [ "../evil.pdf", PDF_BYTES ]
        ]))
      }
    }

    batch = Review::Batch.where(tenant: @tenant).order(:created_at).last
    assert_redirected_to review_batch_path(batch)
    assert_equal "Controller ZIP Upload", batch.name
    assert_match(/Uploaded 1 document to Controller ZIP Upload: 0 ready for review, 1 awaiting extraction, 0 quarantined, 1 rejected, 0 duplicate\./, flash[:notice])
    refute_includes flash[:notice], "evil"
    refute_includes flash[:notice], "invoice.pdf"
  end

  private

  def sign_in
    post session_path, params: { email: @user.email, operator_token: "upload-token" }
  end

  def uploaded_file(filename, content_type, bytes)
    tempfile = Tempfile.new([ "controller-upload", File.extname(filename) ], binmode: true)
    tempfile.write(bytes)
    tempfile.rewind
    @tempfiles << tempfile
    Rack::Test::UploadedFile.new(tempfile.path, content_type, true, original_filename: filename)
  end

  def zip_bytes(entries)
    io = StringIO.new("".b)
    Zip::OutputStream.write_buffer(io) do |zip|
      entries.each do |name, bytes|
        zip.put_next_entry(name)
        zip.write(bytes)
      end
    end
    io.string.b
  end
end
